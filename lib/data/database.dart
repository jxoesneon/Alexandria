import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

/// Production database: a persistent SQLite file under the platform
/// application-support directory (ALX-011). Without this, every persisted
/// table below (credit ledger, daily mint caps, awarded DOIs, work
/// receipts) lived in an in-memory database and reset on restart — the
/// entire ALX-011 persistence layer was inert.
///
/// [LazyDatabase] defers the open until first use, so reading this
/// provider never blocks and never touches path_provider in unit tests.
/// First boot runs Drift's default onCreate; upgrades run the
/// schemaVersion-4 [AppDatabase.migration]. The [AppDatabase] constructor
/// keeps [NativeDatabase.memory] as its default executor so tests stay
/// hermetic — only this provider wires the file-backed executor.
final databaseProvider = Provider<AppDatabase>((ref) {
  // Unit/widget tests have no path_provider platform channel — they get
  // the hermetic in-memory executor (FLUTTER_TEST is always set under
  // `flutter test`). Every other context gets the persistent file.
  final isTest = Platform.environment['FLUTTER_TEST'] == 'true';
  final db = isTest
      ? AppDatabase()
      : AppDatabase(
          LazyDatabase(() async {
            final dir = await getApplicationSupportDirectory();
            return NativeDatabase.createInBackground(
              File(p.join(dir.path, 'alexandria.sqlite')),
            );
          }),
        );
  ref.onDispose(() {
    // LazyDatabase.close() awaits the open future first; when the opener
    // failed (e.g. no path_provider plugin in unit tests) close() would
    // rethrow that failure as an unhandled async error. A database that
    // never opened needs no cleanup — swallow it.
    db.close().catchError((Object _) {});
  });
  return db;
});

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
class CreditTransactions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get type => text()();
  RealColumn get amount => real()();
  TextColumn get description => text()();
  TextColumn get referenceId => text().nullable()();
  TextColumn get hash => text()();
  BoolColumn get isAttested =>
      boolean().withDefault(const Constant(false))();

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
/// (Review REV3 — Safety veto fix). `PreservationBounty.isClaimed` is an
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
  // artifacts keep their declared scheme — rows predating the column
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
  int get schemaVersion => 5;

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
            // Review REV3: durable bounty-claim dedup ledger.
            await m.createTable(claimedBounties);
          }
        },
      );

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
        encryptionKey: Value(data['encryptionKey'] as String?),
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

  Future<List<DateTime>> getUserActivityDates(String publicKey) async {
    return [];
  }

  Future<UserProfile?> getProfileByPublicKey(String publicKey) async {
    final query = select(userProfiles)
      ..where((p) => p.publicKey.equals(publicKey));
    return query.getSingleOrNull();
  }

  Future<void> insertCreditTransaction(Map<String, dynamic> data) async {
    // insertOrIgnore: a primary-key collision is an expected dedup event
    // (e.g. two instances racing the deterministic genesis id), NOT a
    // database failure — the duplicate row is dropped, not thrown.
    await into(creditTransactions).insert(
      CreditTransactionsCompanion.insert(
        id: data['id'] as String,
        timestamp: (data['timestamp'] as DateTime?) ?? DateTime.now(),
        type: data['type'] as String,
        amount: (data['amount'] as num).toDouble(),
        description: data['description'] as String,
        hash: data['hash'] as String,
        referenceId: Value(data['referenceId'] as String?),
        isAttested: Value(data['isAttested'] as bool? ?? false),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<List<Map<String, dynamic>>> getCreditTransactions(
      {int limit = 200}) async {
    final query = select(creditTransactions)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_creditTransactionToMap).toList();
  }

  /// Net ledger balance as `SELECT SUM(amount)` over the FULL history.
  /// Used as the hydration fallback when the replay window truncates —
  /// replaying a partial window would silently compute a wrong balance.
  Future<double> getLedgerBalanceSum() async {
    final total = creditTransactions.amount.sum();
    final query = selectOnly(creditTransactions)..addColumns([total]);
    final row = await query.getSingle();
    return row.read(total) ?? 0.0;
  }

  /// Whether the genesis welcome allocation exists ANYWHERE in the
  /// ledger — queried directly so the check is correct even when the
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

  /// Atomically registers a bounty claim (Review REV3 Safety CAS),
  /// mirroring [insertAwardedDoi]: `INSERT OR IGNORE` on the bounty_id
  /// primary key makes an already-claimed bounty the expected dedup
  /// event, and `changes()` reports whether THIS call inserted the row —
  /// the check-then-insert race window is closed by the primary key,
  /// not by a preceding read. A losing caller sees `false`, never a
  /// thrown PK violation.
  Future<bool> insertClaimedBounty(String bountyId, String cid) async {
    return transaction(() async {
      await into(claimedBounties).insert(
        ClaimedBountiesCompanion.insert(
          bountyId: bountyId,
          cid: cid,
          claimedAt: DateTime.now().millisecondsSinceEpoch,
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
  /// replicated. Never invoked on the success path — a confirmed claim
  /// is permanent.
  Future<void> deleteClaimedBounty(String bountyId) async {
    await (delete(claimedBounties)
          ..where((c) => c.bountyId.equals(bountyId)))
        .go();
  }

  /// Whether [bountyId] has a persisted claim row — survives service
  /// restarts, unlike the in-memory `PreservationBounty.isClaimed` flag.
  Future<bool> isBountyClaimed(String bountyId) async {
    final query = select(claimedBounties)
      ..where((c) => c.bountyId.equals(bountyId));
    final row = await query.getSingleOrNull();
    return row != null;
  }

  Future<void> insertWorkReceipt(Map<String, dynamic> data) async {
    // insertOrIgnore: a receipt re-delivered by the verifier (or re-issued
    // by a retry) collapses onto the same content-derived primary key —
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

  Future<Map<String, dynamic>?> getWorkReceipt(String receiptId) async {
    final query = select(workReceipts)
      ..where((r) => r.receiptId.equals(receiptId));
    final row = await query.getSingleOrNull();
    return row == null ? null : _workReceiptToMap(row);
  }

  /// Atomic spend-dedup primitive (Safety-mandated CAS): a single
  /// `UPDATE work_receipts SET spent=1 WHERE receipt_id=? AND spent=0`.
  /// Returns true iff THIS call consumed the receipt — a lost race
  /// (receipt missing or already spent) yields `updatedRows == 0`, so a
  /// replayed/parallel claim can never double-mint the same receipt.
  Future<bool> claimReceiptAtomically(String receiptId) async {
    final updatedRows = await (update(workReceipts)
          ..where((r) =>
              r.receiptId.equals(receiptId) & r.spent.equals(false)))
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
        'encryptionKey': m.encryptionKey,
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
