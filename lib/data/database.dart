import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/secure_storage_service.dart';

part 'database.g.dart';

/// Production database: a persistent SQLite file under the platform
/// application-support directory (ALX-011). Without this, every persisted
/// table below (credit ledger, daily mint caps, awarded DOIs, work
/// receipts) lived in an in-memory database and reset on restart - the
/// entire ALX-011 persistence layer was inert.
///
/// [LazyDatabase] defers the open until first use, so reading this
/// provider never blocks and never touches path_provider in unit tests.
/// First boot runs Drift's default onCreate; upgrades run the
/// schemaVersion-8 [AppDatabase.migration]. The [AppDatabase] constructor
/// keeps [NativeDatabase.memory] as its default executor so tests stay
/// hermetic - only this provider wires the file-backed executor.
/// Injectable single-writer coordination seam (multi-PROCESS writer
/// residual - see [DatabaseFileGuard]). Tests substitute a fake guard to
/// exercise contention policy without touching the filesystem.
final databaseFileGuardProvider = Provider<DatabaseFileGuard>((ref) {
  return const DatabaseFileGuard();
});

final databaseProvider = Provider<AppDatabase>((ref) {
  // Unit/widget tests have no path_provider platform channel - they get
  // the hermetic in-memory executor (FLUTTER_TEST is always set under
  // `flutter test`). Every other context gets the persistent file.
  final isTest = Platform.environment['FLUTTER_TEST'] == 'true';
  // Read the guard EAGERLY (outside the lazy opener) so the injectable
  // seam is resolved while the provider is certainly alive.
  final guard = ref.read(databaseFileGuardProvider);
  final db = isTest
      ? AppDatabase()
      : AppDatabase(
          LazyDatabase(() async {
            final dir = await getApplicationSupportDirectory();
            final dbFile = File(p.join(dir.path, 'alexandria.sqlite'));
            // Multi-PROCESS writer enforcement: the advisory exclusive
            // lock is acquired BEFORE the SQLite file is opened and held
            // for the process lifetime - a second Alexandria process
            // racing this database fails loudly here instead of
            // interleaving ledger writes (WORKING_ON residual).
            await guard.acquire('${dbFile.path}.lock');
            return NativeDatabase.createInBackground(dbFile);
          }),
        );
  ref.onDispose(() {
    // LazyDatabase.close() awaits the open future first; when the opener
    // failed (e.g. no path_provider plugin in unit tests) close() would
    // rethrow that failure as an unhandled async error. A database that
    // never opened needs no cleanup - swallow it.
    db.close().catchError((Object _) {});
  });
  return db;
});

/// Handle to a held exclusive file lock - see [DatabaseFileGuard].
/// [release] exists for tests and deliberate shutdown paths; the
/// production wiring never calls it (the lock is process-lifetime).
class DatabaseFileLock {
  final String path;
  final RandomAccessFile _file;
  bool _released = false;

  DatabaseFileLock._(this.path, this._file);

  bool get released => _released;

  /// Releases the lock and closes the lockfile handle. Idempotent.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _file.unlock();
    } finally {
      await _file.close();
    }
  }
}

/// Multi-PROCESS single-writer enforcement for `alexandria.sqlite`
/// (WORKING_ON residual: "multi-PROCESS writers remain out of scope" -
/// closed to the extent the platform allows).
///
/// Threat model closed: two OS processes (a duplicate app start, a
/// headless runner alongside the UI, a crashed-then-relaunched instance
/// racing a zombie) opening the SAME SQLite file each get their own
/// connection and would interleave ledger writes with no shared
/// in-memory reconciliation - the durable CAS primitives stop
/// double-mints on the rows they guard, but balance replay, daily-cap
/// counters and the attested-burn accounting were never designed for
/// unsynchronized cross-process mutation. The fix is an OS-level
/// ADVISORY exclusive lock on `<db>.lock` (a sidecar file - locking the
/// SQLite file itself would collide with SQLite's own POSIX locks),
/// acquired BEFORE the file-backed executor opens and held for the
/// process lifetime.
///
/// CONTENTION POLICY - FAIL LOUD, never wait: a second process that
/// cannot acquire throws [StateError] out of the lazy open, so every
/// database use surfaces the failure immediately rather than silently
/// queueing behind a holder that may be a zombie. Waiting was rejected:
/// a wedged holder would park the new process forever with no signal.
///
/// Injectable seam: [databaseFileGuardProvider] supplies the guard so
/// tests can substitute a fake; [acquire] is also directly unit-testable
/// against temp files.
///
/// HONEST BOUNDS that remain:
///  * ADVISORY only - a non-cooperating process (foreign tooling, a
///    build that skips the guard) can still write the file; this is
///    mutual exclusion between cooperating Alexandria processes, not
///    access control.
///  * Network filesystems (NFS/SMB) may not honour flock/LockFile
///    semantics - the app-support directory is local in practice.
///  * The lock auto-releases on process death (OS semantics), so a
///    crashed holder never strands the database.
class DatabaseFileGuard {
  const DatabaseFileGuard();

  /// Locks held for the process lifetime, keyed by lockfile path, so a
  /// second [acquire] of the same path in THIS process returns the
  /// existing handle instead of self-conflicting (flock/LockFile
  /// conflicts are per-handle - a re-entrant acquire would otherwise
  /// report false contention), and so GC can never drop the
  /// [RandomAccessFile] and silently release the lock.
  static final Map<String, DatabaseFileLock> _held =
      <String, DatabaseFileLock>{};

  /// Acquires the exclusive lock on [lockFilePath]. Returns the existing
  /// handle when this process already holds it. Throws [StateError]
  /// when another process (or a non-registry handle) holds the lock -
  /// the documented fail-loud policy.
  Future<DatabaseFileLock> acquire(String lockFilePath) async {
    final existing = _held[lockFilePath];
    if (existing != null && !existing.released) return existing;
    final raf = await File(lockFilePath).open(mode: FileMode.write);
    try {
      // FileLock.exclusive is the NON-BLOCKING exclusive mode in this
      // SDK (the blocking variants are named blockingExclusive/
      // blockingShared): contention throws instead of waiting - the
      // documented fail-loud policy.
      await raf.lock(FileLock.exclusive);
    } catch (e) {
      await raf.close();
      throw StateError(
          'alexandria.sqlite is locked by another Alexandria process '
          '($lockFilePath): refusing to run a second writer against the '
          'same ledger ($e)');
    }
    final lock = DatabaseFileLock._(lockFilePath, raf);
    _held[lockFilePath] = lock;
    return lock;
  }
}

class ContentManifests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('other'))();
  TextColumn get tags => text().nullable()();
  TextColumn get metadata => text().nullable()();
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();
  TextColumn get encryptionKey => text().nullable()();
  DateTimeColumn get lastUpdated => dateTime()();
}

class ContentVersions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get manifestId => integer().references(ContentManifests, #id)();
  TextColumn get cid => text().unique()();
  TextColumn get language => text().withDefault(const Constant('en'))();
  TextColumn get format => text().withDefault(const Constant('bin'))();
  IntColumn get sizeBytes => integer()();
  IntColumn get peerCount => integer().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastHealthCheck => dateTime().nullable()();
  DateTimeColumn get createdData => dateTime()();
  // ALX-010 authenticity: Base58 Ed25519 pubkey of the publishing node and
  // Base64 signature over 'alexandria:version:v1:{manifestUuid}:{cid}'.
  TextColumn get publisherPubkey => text().nullable()();
  TextColumn get signature => text().nullable()();
  // Anti-fragmentation marker, e.g. 'suspect-fragment-of:<cid>'.
  TextColumn get flaggedReason => text().nullable()();
}

class UserProfiles extends Table {
  TextColumn get publicKey => text()();
  IntColumn get reputation => integer().withDefault(const Constant(10))();
  DateTimeColumn get lastActive => dateTime()();

  @override
  Set<Column> get primaryKey => {publicKey};
}

class HonorValidations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get validatorId => text()();
  TextColumn get targetCid => text()();
  IntColumn get score => integer()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get signature => text()();
}

/// Persistent ledger of every Archival Credit mint/spend (ALX-005).
/// [isAttested] is TRUE only when the credit derives from a verifier-signed
/// work receipt whose verifier pubkey differs from the local identity
/// (self-dealing guard, ALX-010).
///
/// [attestedPubkey] (schema v7 - multi-identity sharding residual) scopes
/// an attested MINT row to the canonical prover pubkey whose possession
/// proof earned it. Attested DEBIT rows (egress) and every row written
/// before the column existed carry NULL - the "unscoped" bucket the
/// egress gate counts toward any currently-held key set. The wallet-wide
/// semantics are preserved exactly under single-identity: the only
/// prover key is always the currently-held one.
///
/// [burnedAttested] (schema v8 - durable burn attribution, the
/// sufficiency half of the attested-egress gate) records how much of an
/// ORDINARY (unflagged) debit consumed the attested pool under the
/// service's unattested-first burn rule, computed at write time by the
/// same replay arithmetic the credit ledger's `_rebuildBalance`
/// applies.
/// Attested-flagged egress rows carry their full |amount| here (the
/// entire debit burns attested value by definition), mints and PoR
/// penalty rows carry 0. With this column the durable coverage gate can
/// sum `scoped attested mints − every durable attested burn` - the
/// exact quantity the in-memory `_attestedBurned` cache tracks - making
/// [AppDatabase.insertAttestedDebitIfCovered] a SUFFICIENT condition,
/// not merely a necessary one. Pre-v8 rows are backfilled by the
/// migration replaying the ledger under the identical rule.
class CreditTransactions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get description => text()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get hash => text()();
  BoolColumn get isAttested => boolean().withDefault(const Constant(false))();
  TextColumn get attestedPubkey => text().nullable()();
  RealColumn get burnedAttested => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Persisted daily mint-cap counters, keyed by UTC day ('YYYY-MM-DD') and
/// CreditType name, so daily accrual caps survive restarts (ALX-005 §6.1).
class DailyMinted extends Table {
  TextColumn get dayKey => text()();
  TextColumn get creditType => text()();
  RealColumn get amount => real()();

  @override
  Set<Column> get primaryKey => {dayKey, creditType};
}

/// Permanent registry of DOIs that already received a verification reward,
/// preventing duplicate minting across restarts.
class AwardedDois extends Table {
  TextColumn get doi => text()();
  DateTimeColumn get awardedAt => dateTime()();
  TextColumn get cid => text().nullable()();

  @override
  Set<Column> get primaryKey => {doi};
}

/// Durable registry of preservation bounties this node has claimed
/// (REV3 review - Safety veto fix). `PreservationBounty.isClaimed` is an
/// in-memory flag that any holder of a returned reference could flip
/// back, reopening a claimed bounty for a second escrow payout. This
/// table's primary key is the restart-proof compare-and-swap: a claim
/// wins iff its row insert lands, and only a claim whose asynchronous
/// work-evidence check failed deletes its row so the bounty stays
/// retryable after genuine replication.
class ClaimedBounties extends Table {
  TextColumn get bountyId => text()();
  TextColumn get cid => text()();
  IntColumn get claimedAt => integer()(); // epoch millis

  @override
  Set<Column> get primaryKey => {bountyId};
}

/// Verifier-signed work receipts (ALX-010 / P1). [receiptId] is the sha256 of
/// the canonical receipt body; [verifierSig] is a base64 Ed25519 signature
/// over the domain-separated signing preimage the receipt's own [v] selects
/// (ALX-012). [spent] is the spend-dedup flag set once the receipt is
/// claimed.
class WorkReceipts extends Table {
  TextColumn get receiptId => text()();
  // Per-receipt wire-format version (ALX-012): persisted so foreign
  // artifacts keep their declared scheme - rows predating the column
  // default to the legacy v1 (bare-domain) scheme.
  IntColumn get v => integer().withDefault(const Constant(1))();
  TextColumn get workType => text()(); // 'storage' | 'compute' | 'verification'
  TextColumn get proverPubkey => text()(); // base58 Ed25519
  TextColumn get verifierPubkey => text()(); // base58 Ed25519
  TextColumn get cid => text().nullable()();
  TextColumn get chunkIndices => text()(); // JSON array of ints
  TextColumn get challengeNonce => text()(); // hex
  TextColumn get responseTag => text()(); // hex HMAC
  RealColumn get workUnits => real()();
  RealColumn get amount => real()();
  TextColumn get epoch => text()(); // UTC day
  IntColumn get expiresAt => integer()(); // epoch millis
  TextColumn get evidenceHash => text().nullable()();
  TextColumn get verifierSig => text()(); // base64 Ed25519 signature
  TextColumn get proverSig => text().nullable()(); // prover counter-signature
  BoolColumn get spent => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {receiptId};
}

@DriftDatabase(tables: [
  ContentManifests,
  ContentVersions,
  UserProfiles,
  HonorValidations,
  CreditTransactions,
  DailyMinted,
  AwardedDois,
  WorkReceipts,
  ClaimedBounties,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? NativeDatabase.memory());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(contentVersions, contentVersions.publisherPubkey);
            await m.addColumn(contentVersions, contentVersions.signature);
            await m.addColumn(contentVersions, contentVersions.flaggedReason);
          }
          if (from < 3) {
            await m.createTable(creditTransactions);
            await m.createTable(dailyMinted);
            await m.createTable(awardedDois);
            await m.createTable(workReceipts);
          }
          if (from < 4) {
            // ALX-012: per-receipt wire version. Existing rows hydrate
            // with the column default (1 = legacy bare-domain scheme).
            await m.addColumn(workReceipts, workReceipts.v);
          }
          if (from < 5) {
            // REV3 review: durable bounty-claim dedup ledger.
            await m.createTable(claimedBounties);
          }
          if (from < 6) {
            // (round-5 red finding) scrub legacy plaintext DEKs out of
            // content_manifests.encryption_key - rehomed into secure
            // storage first so no decryptability is lost.
            await _rehomeLegacyManifestKeys();
          }
          if (from < 7) {
            // Multi-identity attested-balance sharding (WORKING_ON
            // residual): attested mint rows gain the canonical prover
            // pubkey that earned them so the egress gate can sum over
            // CURRENTLY-HELD keys only. Pre-existing rows hydrate NULL
            // - the unscoped bucket, which under the single-identity
            // model is exactly the old wallet-wide semantics.
            await m.addColumn(
                creditTransactions, creditTransactions.attestedPubkey);
          }
          if (from < 8) {
            // Durable attested-burn attribution (WORKING_ON residual -
            // insertAttestedDebitIfCovered sufficiency): each debit row
            // records how much of it consumed the attested pool under
            // the unattested-first rule, so the durable egress gate can
            // sum mints-minus-burns instead of seeing mints alone.
            // The column lands defaulted to 0, then the backfill
            // replays the ledger under the service's own burn rule so
            // pre-v8 rows carry the same values the service computes.
            await m.addColumn(
                creditTransactions, creditTransactions.burnedAttested);
            await _backfillBurnedAttested();
          }
        },
        // Same sweep on every open: a row whose DEK could not be rehomed
        // during the v6 upgrade (keychain momentarily unavailable) keeps
        // its key - data preservation beats scrub-once - and is retried
        // here until the write to secure storage succeeds.
        beforeOpen: (details) async {
          await _rehomeLegacyManifestKeys();
        },
      );

  /// (round-5 red finding) Moves any surviving plaintext DEK in
  /// [ContentManifests.encryptionKey] into secure storage under
  /// `dek_<uuid>` - the same location ContentRepository.createContent
  /// has written since the round-2 fix - then NULLs the column.
  ///
  /// Ordering: the secure-storage write lands BEFORE the column is
  /// nulled, so a database upgraded from a pre-round-2 build never
  /// loses the only copy of a DEK. When the keychain is unreachable
  /// (headless/unit-test contexts have no flutter_secure_storage
  /// channel) the row keeps its key and a later [beforeOpen] retries -
  /// the plugin-facing leak is closed regardless by the projected view
  /// in PluginContentRepository, and no first-party code reads the
  /// column.
  Future<void> _rehomeLegacyManifestKeys() async {
    final List<ContentManifest> rows;
    try {
      rows = await (select(contentManifests)
            ..where((m) => m.encryptionKey.isNotNull()))
          .get();
    } catch (_) {
      return; // table absent on a pre-create open - nothing to rehome
    }
    if (rows.isEmpty) return;
    SecureStorageService? storage;
    for (final row in rows) {
      final key = row.encryptionKey;
      if (key == null) continue;
      try {
        storage ??= SecureStorageService();
        await storage.write('dek_${row.uuid}', key);
      } catch (_) {
        continue; // keychain unreachable - keep the row, retry next open
      }
      await (update(contentManifests)..where((m) => m.uuid.equals(row.uuid)))
          .write(const ContentManifestsCompanion(encryptionKey: Value(null)));
    }
  }

  /// Emergency data wipe: deletes every row in every table inside one
  /// transaction and resets AUTOINCREMENT counters, leaving the schema
  /// exactly as a fresh install's `onCreate` produced it. Used by
  /// Settings → Emergency Data Wipe; secure-storage keys and the IPFS
  /// repo are cleared by the caller.
  Future<void> wipeAllData() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
      // sqlite_sequence only exists while an AUTOINCREMENT table does
      // (ContentManifests/ContentVersions); the reset makes a post-wipe
      // insert start at 1 like a fresh install, and no-ops on executors
      // where the table was never created.
      try {
        await customStatement('DELETE FROM sqlite_sequence');
      } catch (_) {}
    });
  }

  /// v7→v8 backfill for [CreditTransactions.burnedAttested]: replays the
  /// persisted ledger in chronological order under the SAME burn rule
  /// `CreditService._rebuildBalance`/`_burnForDebit` apply at runtime,
  /// and stamps each row with the attested share it consumed. Rules
  /// (mirrored exactly):
  ///  * amount >= 0 (mint): burn 0; attested mints accrue to the pool.
  ///  * storageReward debit (PoR penalty): burn 0 - slashing may never
  ///    eat attested value; the runtime floor clamps the applied part.
  ///  * isAttested debit (egress): the WHOLE debit burns attested
  ///    value - it settles against the attested pool directly.
  ///  * any other debit: burn = spend − max(pre-debit unattested, 0),
  ///    where unattested = balance − (attestedMinted − attestedBurned).
  /// Ordering is `timestamp ASC, rowid ASC` - the exact replay order the
  /// service hydrates with (rowid = insertion chronology tiebreaker).
  Future<void> _backfillBurnedAttested() async {
    final rows = await customSelect(
      'SELECT id, amount, is_attested, type FROM credit_transactions '
      'ORDER BY timestamp ASC, rowid ASC',
      readsFrom: {creditTransactions},
    ).get();
    var balance = 0.0;
    var attestedMinted = 0.0;
    var attestedBurned = 0.0;
    for (final row in rows) {
      final id = row.read<String>('id');
      final amount = row.read<double>('amount');
      final isAttested = row.read<bool>('is_attested');
      final type = row.read<String>('type');
      var burn = 0.0;
      if (amount >= 0) {
        balance += amount;
        if (isAttested) attestedMinted += amount;
      } else if (type == 'storageReward') {
        // PoR penalty: floored at the running balance, never attested.
        final applied = (-amount).clamp(0.0, balance);
        balance -= applied;
      } else if (isAttested) {
        burn = -amount;
        attestedBurned += burn;
        balance += amount;
      } else {
        final spend = -amount;
        final unattested = balance - (attestedMinted - attestedBurned);
        final b = spend - (unattested > 0.0 ? unattested : 0.0);
        if (b > 0.0) {
          burn = b;
          attestedBurned += b;
        }
        balance += amount;
      }
      if (burn != 0.0) {
        await customStatement(
          'UPDATE credit_transactions SET burned_attested = ? '
          'WHERE id = ?',
          [burn, id],
        );
      }
    }
  }

  Future<void> insertManifest(Map<String, dynamic> data) async {
    await into(contentManifests).insert(
      ContentManifestsCompanion.insert(
        uuid: data['uuid'] as String,
        title: data['title'] as String,
        lastUpdated: (data['lastUpdated'] as DateTime?) ?? DateTime.now(),
        author: Value(data['author'] as String?),
        description: Value(data['description'] as String?),
        category: Value(data['category'] as String? ?? 'other'),
        tags: Value(data['tags'] as String?),
        metadata: Value(data['metadata'] as String?),
        isEncrypted: Value(data['isEncrypted'] as bool? ?? false),
        // (round-5 red finding) `encryptionKey` in the input map is
        // deliberately NOT forwarded: nothing legitimate has written the
        // column since the round-2 fix moved DEKs to secure storage, and
        // accepting it would keep the plaintext-DEK column writable.
        encryptionKey: const Value(null),
      ),
    );
  }

  Future<Map<String, dynamic>?> getManifestByUuid(String uuid) async {
    final query = select(contentManifests)..where((m) => m.uuid.equals(uuid));
    final row = await query.getSingleOrNull();
    return row == null ? null : _manifestToMap(row);
  }

  Future<List<ContentManifest>> getAllManifests() async {
    return select(contentManifests).get();
  }

  Future<void> insertVersion(Map<String, dynamic> data) async {
    await into(contentVersions).insert(
      ContentVersionsCompanion.insert(
        manifestId: data['manifestId'] as int,
        cid: data['cid'] as String,
        sizeBytes: data['sizeBytes'] as int? ?? 0,
        createdData: (data['createdData'] as DateTime?) ?? DateTime.now(),
        language: Value(data['language'] as String? ?? 'en'),
        format: Value(data['format'] as String? ?? 'bin'),
        peerCount: Value(data['peerCount'] as int? ?? 0),
        isPinned: Value(data['isPinned'] as bool? ?? true),
        lastHealthCheck: Value(data['lastHealthCheck'] as DateTime?),
        publisherPubkey: Value(data['publisherPubkey'] as String?),
        signature: Value(data['signature'] as String?),
        flaggedReason: Value(data['flaggedReason'] as String?),
      ),
    );
  }

  Future<Map<String, dynamic>?> getVersionByCid(String cid) async {
    final query = select(contentVersions)..where((v) => v.cid.equals(cid));
    final row = await query.getSingleOrNull();
    return row == null ? null : _versionToMap(row);
  }

  Future<List<ContentVersion>> getEndangeredVersions(int threshold) async {
    final query = select(contentVersions)
      ..where((v) => v.peerCount.isSmallerThanValue(threshold));
    return query.get();
  }

  Future<List<ContentVersion>> getVersionsForManifest(int manifestId) async {
    final query = select(contentVersions)
      ..where((v) => v.manifestId.equals(manifestId));
    return query.get();
  }

  Future<void> insertHonorValidation({
    required String validatorId,
    required String targetCid,
    required int score,
    required String signature,
  }) async {
    await into(honorValidations).insert(
      HonorValidationsCompanion.insert(
        validatorId: validatorId,
        targetCid: targetCid,
        score: score,
        timestamp: DateTime.now(),
        signature: signature,
      ),
    );
  }

  /// Newest row per (validatorId, targetCid) wins on replay — mirrors
  /// HonorSystem's one-ballot-per-validator dedup.
  Future<List<HonorValidation>> getAllHonorValidations() {
    return select(honorValidations).get();
  }

  /// Rewrites every ballot cast under a legacy placeholder validator id
  /// (e.g. 'me') onto the real identity — preserves the user's explicit
  /// vote while making the stored validator verifiable.
  Future<int> remapHonorValidationValidator({
    required String from,
    required String to,
  }) {
    return (update(honorValidations)..where((v) => v.validatorId.equals(from)))
        .write(HonorValidationsCompanion(validatorId: Value(to)));
  }

  /// Removes ballots recorded under a placeholder validator id (e.g.
  /// 'self') — self-attestations are not community trust and must not be
  /// replayed into the tally.
  Future<int> deleteHonorValidationsByValidator(String validatorId) {
    return (delete(honorValidations)
          ..where((v) => v.validatorId.equals(validatorId)))
        .go();
  }

  Future<List<DateTime>> getUserActivityDates(String publicKey) async {
    return [];
  }

  Future<UserProfile?> getProfileByPublicKey(String publicKey) async {
    final query = select(userProfiles)
      ..where((p) => p.publicKey.equals(publicKey));
    return query.getSingleOrNull();
  }

  static CreditTransactionsCompanion _creditTxCompanion(
          Map<String, dynamic> data) =>
      CreditTransactionsCompanion.insert(
        id: data['id'] as String,
        timestamp: (data['timestamp'] as DateTime?) ?? DateTime.now(),
        type: data['type'] as String,
        amount: (data['amount'] as num).toDouble(),
        description: data['description'] as String,
        hash: data['hash'] as String,
        referenceId: Value(data['referenceId'] as String?),
        isAttested: Value(data['isAttested'] as bool? ?? false),
        // Canonical prover-pubkey scope for attested mints (schema v7);
        // NULL on debits and legacy rows = the unscoped bucket.
        attestedPubkey: Value(data['attestedPubkey'] as String?),
        // Durable attested-burn attribution (schema v8): how much of a
        // debit consumed the attested pool - the sufficiency input of
        // [insertAttestedDebitIfCovered].
        burnedAttested:
            Value((data['burnedAttested'] as num?)?.toDouble() ?? 0.0),
      );

  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    // insertOrIgnore: a primary-key collision is an expected dedup event
    // (e.g. two instances racing the deterministic genesis id), NOT a
    // database failure - the duplicate row is dropped, not thrown.
    await into(creditTransactions).insert(
      _creditTxCompanion(data),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// CAS variant of [insertCreditTransaction] (multi-instance stale-view
  /// reconciliation): identical `INSERT OR IGNORE` semantics, but run
  /// inside a transaction and reports via `changes()` whether THIS call
  /// actually landed the row. A deterministic-id writer (bounty payout,
  /// escrow release/hold) that gets `false` back lost the durable race -
  /// the primary key already belongs to another writer's row, so the
  /// caller's in-memory mint must reconcile against the canonical row
  /// instead of trusting its own write. Same pattern as
  /// [insertAwardedDoi]/[insertClaimedBounty].
  Future<bool> insertCreditTransactionIfAbsent(
      Map<String, dynamic> data) async {
    return transaction(() async {
      await into(creditTransactions).insert(
        _creditTxCompanion(data),
        mode: InsertMode.insertOrIgnore,
      );
      // changes() reflects this connection's last write; inside the
      // transaction nothing can interleave, so it reports exactly
      // whether the INSERT OR IGNORE above landed.
      final row = await customSelect('SELECT changes() AS c').getSingle();
      return row.read<int>('c') > 0;
    });
  }

  /// The persisted `amount` of the ledger row with primary key [id], or
  /// null when no such row exists. Used by write-time reconciliation:
  /// after a deterministic-id insert loses (or to check which of two
  /// racing writes survived), the caller reads back the canonical row
  /// and aligns its in-memory mint with what the ledger actually kept.
  Future<double?> getCreditTransactionAmount(String id) async {
    final query = selectOnly(creditTransactions)
      ..addColumns([creditTransactions.amount])
      ..where(creditTransactions.id.equals(id));
    final row = await query.getSingleOrNull();
    return row?.read(creditTransactions.amount);
  }

  /// Escrow-hold candidate rows for [referenceId] - the durable half of
  /// `CreditService.releaseEscrow`'s hold scan (RE-W residual closure).
  /// A TARGETED read on `reference_id` returning full rows (amounts
  /// included), NOT the ~100k-row hydration replay window, so a hold row
  /// older than the window stays refundable.
  ///
  /// The SQL pre-filter mirrors the releasable-hold shape - a negative
  /// `priorityAccessDebit` carrying either the non-forgeable
  /// `tx_escrow_hold_<ref>_<micros>_<seq>` id (only debitEscrow can mint
  /// it) or, for rows written by pre-REV4a builds, the EXACT description
  /// `Bounty Escrow Hold (<referenceId>)` (unforgeable because
  /// spendCredits always appends its ' (incl. 5% treasury fee)' suffix -
  /// a `contains` match would be forgeable and is deliberately not used).
  /// The service re-applies the full `_isReleasableHold` predicate
  /// (including the non-finite-amount guard) over these candidates, so
  /// this listing may over-select but never under-select.
  Future<List<Map<String, dynamic>>> getEscrowHoldRows(
      String referenceId) async {
    final query = select(creditTransactions)
      ..where((t) =>
          t.referenceId.equals(referenceId) &
          t.type.equals('priorityAccessDebit') &
          t.amount.isSmallerThanValue(0.0) &
          (t.id.like('tx_escrow_hold_%') |
              t.description.equals('Bounty Escrow Hold ($referenceId)')));
    final rows = await query.get();
    // LIKE treats '_'/'%' in the prefix as wildcards - re-filter the id
    // exactly (the description leg is already an equality match) so only
    // literal prefix matches survive.
    return rows
        .where((r) =>
            r.id.startsWith('tx_escrow_hold_') ||
            r.description == 'Bounty Escrow Hold ($referenceId)')
        .map(_creditTransactionToMap)
        .toList();
  }

  /// Durable authority for the attested-egress gate (multi-instance
  /// stale-view reconciliation + prover-key scoping): inserts the
  /// attested debit row in [data] ONLY while the ledger's own attested
  /// sum over the CURRENTLY-HELD keys still covers [requiredCredits].
  ///
  /// `attested_pubkey IS NULL` rows are the unscoped bucket - pre-v7
  /// legacy mints (wallet-scoped under single-identity) and the egress
  /// debit rows themselves - and count toward any held-key set. Rows
  /// scoped to a prover key count only when that canonical key is in
  /// [heldAttestedPubkeys]: value minted under a retired or foreign key
  /// can never back an egress for keys the node no longer holds.
  ///
  /// The second clause (`available <= ledgerNet`) is the balance floor:
  /// a debit can never exceed the durable ledger's net.
  ///
  /// SUFFICIENT since schema v8 (`burned_attested`): the durable sum
  /// subtracts EVERY recorded attested burn - egress debits AND the
  /// attested share ordinary (unflagged) debits consumed - so the gate
  /// computes the same `mints − burns` quantity the service's in-memory
  /// `_attestedBurned` cache tracks. A pass means the ledger itself
  /// covers the egress under the unattested-first rule, not merely that
  /// enough attested mints exist in isolation. Rows carry their own
  /// burn attribution, so no order-dependent replay state is needed at
  /// gate time. The egress row being inserted is stamped with
  /// `burned_attested = requiredCredits` here - it burns attested value
  /// in full by definition, so the next gate evaluation sees its cost.
  /// Returns false (and writes nothing) when either condition fails or
  /// the id was already taken.
  Future<bool> insertAttestedDebitIfCovered(
    Map<String, dynamic> data, {
    required Set<String> heldAttestedPubkeys,
    required double requiredCredits,
  }) async {
    return transaction(() async {
      final total = creditTransactions.amount.sum();
      // Scoped attested MINTS only (amount > 0): unscoped-bucket rows
      // (NULL) plus rows scoped to a currently-held key. Egress rows are
      // isAttested debits - their cost is counted through
      // burned_attested below, never as negative mints.
      final scopedQuery = selectOnly(creditTransactions)
        ..addColumns([total])
        ..where(creditTransactions.isAttested.equals(true) &
            creditTransactions.amount.isBiggerThanValue(0.0) &
            (heldAttestedPubkeys.isEmpty
                // Empty held set: only the unscoped bucket is reachable.
                ? creditTransactions.attestedPubkey.isNull()
                : creditTransactions.attestedPubkey.isNull() |
                    creditTransactions.attestedPubkey
                        .isIn(heldAttestedPubkeys)));
      final minted = (await scopedQuery.getSingleOrNull())?.read(total) ?? 0.0;
      // Every durable attested burn, wallet-wide (internal burns draw
      // on the all-keys pool - key scoping applies to mints only).
      final burnedCol = creditTransactions.burnedAttested.sum();
      final burnedQuery = selectOnly(creditTransactions)
        ..addColumns([burnedCol]);
      final burned =
          (await burnedQuery.getSingleOrNull())?.read(burnedCol) ?? 0.0;
      final totalQuery = selectOnly(creditTransactions)..addColumns([total]);
      final ledgerNet =
          (await totalQuery.getSingleOrNull())?.read(total) ?? 0.0;
      var available = minted - burned;
      if (available > ledgerNet) available = ledgerNet;
      if (!(available >= requiredCredits)) return false;
      // The egress row burns attested value in full - stamp it so the
      // durable burn sum stays sufficient for the NEXT writer even if
      // the caller forgot the column.
      final stamped = <String, dynamic>{...data}..['burnedAttested'] =
          requiredCredits;
      await into(creditTransactions).insert(
        _creditTxCompanion(stamped),
        mode: InsertMode.insertOrIgnore,
      );
      final row = await customSelect('SELECT changes() AS c').getSingle();
      return row.read<int>('c') > 0;
    });
  }

  Future<List<Map<String, dynamic>>> getCreditTransactions(
      {int limit = 200}) async {
    final query = select(creditTransactions)
      // dateTime() persists at SECOND resolution - same-second rows
      // need a deterministic tiebreaker or the hydration replay sees
      // them in arbitrary order (round-1 phantom-debt flake: a penalty
      // replayed while the running balance is 0 floors to a no-op and
      // phantom "debt" divergence appears). rowid is insertion order,
      // i.e. true chronology for a single writer.
      ..orderBy([
        (t) => OrderingTerm.desc(t.timestamp),
        (t) => OrderingTerm.desc(t.rowId),
      ])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_creditTransactionToMap).toList();
  }

  /// Net ledger balance as `SELECT SUM(amount)` over the FULL history.
  /// Used as the hydration fallback when the replay window truncates -
  /// replaying a partial window would silently compute a wrong balance.
  Future<double> getLedgerBalanceSum() async {
    final total = creditTransactions.amount.sum();
    final query = selectOnly(creditTransactions)..addColumns([total]);
    final row = await query.getSingle();
    return row.read(total) ?? 0.0;
  }

  /// Whether the genesis welcome allocation exists ANYWHERE in the
  /// ledger - queried directly so the check is correct even when the
  /// hydration replay window truncates older rows (the in-memory scan
  /// would miss a genesis row beyond the window and re-grant it).
  /// Literals mirror CreditService._kGenesisTxId / _kGenesisMarker.
  Future<bool> hasGenesisTransaction() async {
    final query = select(creditTransactions)
      ..where((t) =>
          t.id.equals('tx_genesis') |
          t.description.contains('Genesis Common Heritage'))
      ..limit(1);
    return (await query.get()).isNotEmpty;
  }

  /// Whether a credit-transaction row with EXACTLY this primary key
  /// exists - a direct point query like [hasGenesisTransaction], never
  /// a scan of the hydrated replay window (which silently truncates
  /// rows beyond its limit and would misread a settled payout as
  /// missing). The bounty-claim crash-window reconciler uses this to
  /// prove a payout durably landed (REV4 review, Safety-mandated).
  Future<bool> hasCreditTransaction(String id) async {
    final query = select(creditTransactions)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    return row != null;
  }

  /// All credit-transaction primary keys carrying [idPrefix] - a
  /// targeted index read, NEVER the hydrated replay window (which
  /// silently truncates rows beyond its limit). Rebuilding dedup sets
  /// (`tx_bounty_payout_*`, `tx_escrow_release_*`, `tx_escrow_hold_*`)
  /// from the windowed replay would false-orphan old rows and re-enable
  /// double-mints; prefix reads are complete regardless of table size.
  Future<List<String>> getCreditTransactionIdsWithPrefix(
      String idPrefix) async {
    final query = selectOnly(creditTransactions)
      ..addColumns([creditTransactions.id])
      ..where(creditTransactions.id.like('$idPrefix%'));
    final rows = await query.get();
    // LIKE treats '_'/'%' in the prefix as wildcards - re-filter
    // exactly so only literal prefix matches survive.
    return rows
        .map((r) => r.read(creditTransactions.id)!)
        .where((id) => id.startsWith(idPrefix))
        .toList();
  }

  /// Returns persisted daily mint totals for [dayKey] as type → amount.
  Future<Map<String, double>> getDailyMinted(String dayKey) async {
    final query = select(dailyMinted)..where((d) => d.dayKey.equals(dayKey));
    final rows = await query.get();
    return {for (final row in rows) row.creditType: row.amount};
  }

  Future<void> upsertDailyMinted(
      String dayKey, String creditType, double amount) async {
    await into(dailyMinted).insertOnConflictUpdate(
      DailyMintedCompanion.insert(
        dayKey: dayKey,
        creditType: creditType,
        amount: amount,
      ),
    );
  }

  /// Atomically registers a DOI payout. `INSERT OR IGNORE` makes a
  /// duplicate DOI the expected dedup event rather than a storage error;
  /// returns true iff THIS call inserted the row, so callers can close
  /// the hasAwardedDoi-then-insert race window: a losing duplicate claim
  /// sees `false`, never a thrown PK violation.
  Future<bool> insertAwardedDoi(String doi, {String? cid}) async {
    return transaction(() async {
      await into(awardedDois).insert(
        AwardedDoisCompanion.insert(
          doi: doi,
          awardedAt: DateTime.now(),
          cid: Value(cid),
        ),
        mode: InsertMode.insertOrIgnore,
      );
      // changes() reflects this connection's last write; inside the
      // transaction nothing can interleave, so it reports exactly
      // whether the INSERT OR IGNORE above landed.
      final row = await customSelect('SELECT changes() AS c').getSingle();
      return row.read<int>('c') > 0;
    });
  }

  Future<bool> hasAwardedDoi(String doi) async {
    final query = select(awardedDois)..where((d) => d.doi.equals(doi));
    final row = await query.getSingleOrNull();
    return row != null;
  }

  /// Atomically registers a bounty claim (REV3 review Safety CAS),
  /// mirroring [insertAwardedDoi]: `INSERT OR IGNORE` on the bounty_id
  /// primary key makes an already-claimed bounty the expected dedup
  /// event, and `changes()` reports whether THIS call inserted the row -
  /// the check-then-insert race window is closed by the primary key,
  /// not by a preceding read. A losing caller sees `false`, never a
  /// thrown PK violation.
  ///
  /// [claimedAt] defaults to the insertion time; callers that later
  /// need to release EXACTLY the row this call inserted pass an
  /// explicit timestamp they can hand to
  /// [deleteClaimedBountyIfClaimedAt].
  Future<bool> insertClaimedBounty(String bountyId, String cid,
      {int? claimedAt}) async {
    return transaction(() async {
      await into(claimedBounties).insert(
        ClaimedBountiesCompanion.insert(
          bountyId: bountyId,
          cid: cid,
          claimedAt: claimedAt ?? DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
      // changes() reflects this connection's last write; inside the
      // transaction nothing can interleave, so it reports exactly
      // whether the INSERT OR IGNORE above landed.
      final row = await customSelect('SELECT changes() AS c').getSingle();
      return row.read<int>('c') > 0;
    });
  }

  /// Releases a claim whose asynchronous work-evidence check failed, so
  /// the bounty can be claimed again once the CID is genuinely
  /// replicated. Never invoked on the success path - a confirmed claim
  /// is permanent.
  Future<void> deleteClaimedBounty(String bountyId) async {
    await (delete(claimedBounties)..where((c) => c.bountyId.equals(bountyId)))
        .go();
  }

  /// Ownership-aware claim-row release (E-REV4b F4/F5): deletes the row
  /// for [bountyId] ONLY while its `claimed_at` still equals
  /// [claimedAt], and reports the number of rows removed. A result of
  /// 0 means the row vanished or was replaced by a newer claim attempt
  /// between the caller's observation and this delete - in that case
  /// the row is somebody else's and must be left standing.
  ///
  /// Bare [deleteClaimedBounty] remains the right tool for the claim
  /// healer (a loser may legitimately remove a genuinely stale or
  /// orphaned winner row regardless of who owns it), but every
  /// self-cleanup path - a claim releasing ITS OWN row, the startup
  /// sweep acting on a snapshot - must go through this method:
  /// deleting by bare id would tear down a row a racing claim attempt
  /// re-inserted in the gap.
  Future<int> deleteClaimedBountyIfClaimedAt(
      String bountyId, int claimedAt) async {
    return (delete(claimedBounties)
          ..where((c) =>
              c.bountyId.equals(bountyId) & c.claimedAt.equals(claimedAt)))
        .go();
  }

  /// Whether [bountyId] has a persisted claim row - survives service
  /// restarts, unlike the in-memory `PreservationBounty.isClaimed` flag.
  Future<bool> isBountyClaimed(String bountyId) async {
    final query = select(claimedBounties)
      ..where((c) => c.bountyId.equals(bountyId));
    final row = await query.getSingleOrNull();
    return row != null;
  }

  /// The persisted claim timestamp (epoch millis) for [bountyId], or
  /// null when no claim row exists. The crash-window reconciler uses
  /// this to tell a YOUNG in-flight claim (leave standing - a live
  /// claimant still owns it) apart from a stale row (heal it) or an
  /// orphaned one (deleted between the lost CAS and this read).
  Future<int?> getClaimedBountyClaimedAt(String bountyId) async {
    final query = select(claimedBounties)
      ..where((c) => c.bountyId.equals(bountyId));
    final row = await query.getSingleOrNull();
    return row?.claimedAt;
  }

  /// All claim rows whose claimedAt predates [epochMillis] - the
  /// startup reconciliation sweep's candidate set: stale rows nobody
  /// will ever retry (claims stranded by a crash between the CAS and
  /// the payout, or by a claim-release delete that threw).
  Future<List<ClaimedBounty>> getClaimedBountiesOlderThan(
      int epochMillis) async {
    final query = select(claimedBounties)
      ..where((c) => c.claimedAt.isSmallerThanValue(epochMillis));
    return query.get();
  }

  Future<void> insertWorkReceipt(Map<String, dynamic> data) async {
    // insertOrIgnore: a receipt re-delivered by the verifier (or re-issued
    // by a retry) collapses onto the same content-derived primary key -
    // a duplicate is expected, not a database error.
    await into(workReceipts).insert(
      WorkReceiptsCompanion.insert(
        receiptId: data['receiptId'] as String,
        // Tolerant parse: callers/rows that omit `v` fall back to the
        // legacy v1 scheme rather than failing the insert.
        v: Value((data['v'] as num?)?.toInt() ?? 1),
        workType: data['workType'] as String,
        proverPubkey: data['proverPubkey'] as String,
        verifierPubkey: data['verifierPubkey'] as String,
        chunkIndices: data['chunkIndices'] as String,
        challengeNonce: data['challengeNonce'] as String,
        responseTag: data['responseTag'] as String,
        workUnits: (data['workUnits'] as num).toDouble(),
        amount: (data['amount'] as num).toDouble(),
        epoch: data['epoch'] as String,
        expiresAt: data['expiresAt'] as int,
        verifierSig: data['verifierSig'] as String,
        createdAt: (data['createdAt'] as DateTime?) ?? DateTime.now(),
        cid: Value(data['cid'] as String?),
        evidenceHash: Value(data['evidenceHash'] as String?),
        proverSig: Value(data['proverSig'] as String?),
        spent: Value(data['spent'] as bool? ?? false),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Conditional signature upgrade for an existing receipt row
  /// (ALX-012 §5.8 - `insertWorkReceipt` first-insert-wins residual):
  /// a receiptId that first arrived UNSIGNED must not permanently block
  /// the later SIGNED redelivery of the same artifact.
  ///
  /// Fills [verifierSig]/[proverSig] ONLY while the stored column is
  /// still empty - a signed row is never touched, so an upgrade can
  /// never downgrade or overwrite a signature (a second, different
  /// signature for the same receiptId would be a conflicting-attestation
  /// event: first-signed-wins, like first-insert-wins for the body).
  ///
  /// CRYPTO BOUNDARY: this DAO is a syntactic conditional write - it
  /// does NOT verify the signatures. The verification guard lives in
  /// the trust-aware ingest path
  /// (`CreditService.ingestWorkReceipt`), which checks the signatures
  /// in-path BEFORE calling this; direct DAO callers get the raw
  /// upgrade primitive only. Returns true iff a column was filled.
  Future<bool> upgradeWorkReceiptSignatures(
    String receiptId, {
    String? verifierSig,
    String? proverSig,
  }) async {
    return transaction(() async {
      final row = await (select(workReceipts)
            ..where((r) => r.receiptId.equals(receiptId)))
          .getSingleOrNull();
      if (row == null) return false;
      final upgradeVerifier = verifierSig != null &&
          verifierSig.isNotEmpty &&
          row.verifierSig.isEmpty;
      final upgradeProver = proverSig != null &&
          proverSig.isNotEmpty &&
          (row.proverSig == null || row.proverSig!.isEmpty);
      if (!upgradeVerifier && !upgradeProver) return false;
      await (update(workReceipts)..where((r) => r.receiptId.equals(receiptId)))
          .write(WorkReceiptsCompanion(
        verifierSig:
            upgradeVerifier ? Value(verifierSig) : const Value.absent(),
        proverSig: upgradeProver ? Value(proverSig) : const Value.absent(),
      ));
      return true;
    });
  }

  Future<Map<String, dynamic>?> getWorkReceipt(String receiptId) async {
    final query = select(workReceipts)
      ..where((r) => r.receiptId.equals(receiptId));
    final row = await query.getSingleOrNull();
    return row == null ? null : _workReceiptToMap(row);
  }

  /// Atomic spend-dedup primitive (Safety-mandated CAS): a single
  /// `UPDATE work_receipts SET spent=1 WHERE receipt_id=? AND spent=0`.
  /// Returns true iff THIS call consumed the receipt - a lost race
  /// (receipt missing or already spent) yields `updatedRows == 0`, so a
  /// replayed/parallel claim can never double-mint the same receipt.
  Future<bool> claimReceiptAtomically(String receiptId) async {
    final updatedRows = await (update(workReceipts)
          ..where((r) => r.receiptId.equals(receiptId) & r.spent.equals(false)))
        .write(const WorkReceiptsCompanion(spent: Value(true)));
    return updatedRows > 0;
  }

  /// Legacy self-issue spend marker, kept for the local PoR claim path.
  /// Implemented via the same conditional-update semantics as
  /// [claimReceiptAtomically]: the write is a no-op when the receipt
  /// is already spent, so the legacy path can't resurrect a consumed
  /// receipt either.
  Future<void> markReceiptSpent(String receiptId) async {
    await claimReceiptAtomically(receiptId);
  }

  static Map<String, dynamic> _creditTransactionToMap(CreditTransaction t) => {
        'id': t.id,
        'timestamp': t.timestamp,
        'type': t.type,
        'amount': t.amount,
        'description': t.description,
        'referenceId': t.referenceId,
        'hash': t.hash,
        'isAttested': t.isAttested,
        'attestedPubkey': t.attestedPubkey,
        'burnedAttested': t.burnedAttested,
      };

  static Map<String, dynamic> _workReceiptToMap(WorkReceipt r) => {
        'receiptId': r.receiptId,
        'v': r.v,
        'workType': r.workType,
        'proverPubkey': r.proverPubkey,
        'verifierPubkey': r.verifierPubkey,
        'cid': r.cid,
        'chunkIndices': r.chunkIndices,
        'challengeNonce': r.challengeNonce,
        'responseTag': r.responseTag,
        'workUnits': r.workUnits,
        'amount': r.amount,
        'epoch': r.epoch,
        'expiresAt': r.expiresAt,
        'evidenceHash': r.evidenceHash,
        'verifierSig': r.verifierSig,
        'proverSig': r.proverSig,
        'spent': r.spent,
        'createdAt': r.createdAt,
      };

  static Map<String, dynamic> _manifestToMap(ContentManifest m) => {
        'id': m.id,
        'uuid': m.uuid,
        'title': m.title,
        'author': m.author,
        'description': m.description,
        'category': m.category,
        'tags': m.tags,
        'metadata': m.metadata,
        'isEncrypted': m.isEncrypted,
        // (round-5 red finding) the key-material column is projected
        // out of every map view - a caller holding the map must not
        // find a plaintext DEK on a legacy (pre-scrub) row.
        'encryptionKey': null,
        'lastUpdated': m.lastUpdated,
      };

  static Map<String, dynamic> _versionToMap(ContentVersion v) => {
        'id': v.id,
        'manifestId': v.manifestId,
        'cid': v.cid,
        'language': v.language,
        'format': v.format,
        'sizeBytes': v.sizeBytes,
        'peerCount': v.peerCount,
        'isPinned': v.isPinned,
        'lastHealthCheck': v.lastHealthCheck,
        'createdData': v.createdData,
        'publisherPubkey': v.publisherPubkey,
        'signature': v.signature,
        'flaggedReason': v.flaggedReason,
      };
}
