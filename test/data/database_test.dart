import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';

void main() {
  group('AppDatabase public API', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('schemaVersion is 5', () {
      expect(db.schemaVersion, equals(5));
    });

    test('insert and retrieve a manifest by uuid', () async {
      final now = DateTime.now();
      await db.insertManifest({
        'uuid': 'uuid-1',
        'title': 'The Republic',
        'author': 'Plato',
        'description': 'A philosophical work',
        'category': 'Philosophy',
        'tags': 'politics',
        'metadata': '{}',
        'isEncrypted': false,
        'lastUpdated': now,
      });

      final manifest = await db.getManifestByUuid('uuid-1');
      expect(manifest, isNotNull);
      expect(manifest!['title'], equals('The Republic'));
      expect(manifest['author'], equals('Plato'));
      expect(manifest['category'], equals('Philosophy'));
      expect(manifest['lastUpdated'], isA<DateTime>());
      expect(manifest['isEncrypted'], isFalse);
      expect(manifest['uuid'], equals('uuid-1'));
      expect(manifest['id'], isA<int>());
    });

    test('getManifestByUuid returns null for missing uuid', () async {
      final manifest = await db.getManifestByUuid('missing');
      expect(manifest, isNull);
    });

    test('getAllManifests returns all inserted manifests', () async {
      await db.insertManifest({
        'uuid': 'all-1',
        'title': 'A',
        'lastUpdated': DateTime.now(),
      });
      await db.insertManifest({
        'uuid': 'all-2',
        'title': 'B',
        'lastUpdated': DateTime.now(),
      });

      final manifests = await db.getAllManifests();
      expect(manifests.length, equals(2));
      expect(manifests.map((m) => m.title), containsAll(['A', 'B']));
    });

    test('insert and retrieve a version by cid', () async {
      await db.insertManifest({
        'uuid': 'ver-1',
        'title': 'Versioned Content',
        'lastUpdated': DateTime.now(),
      });
      final manifest = await db.getManifestByUuid('ver-1');
      final manifestId = manifest!['id'] as int;

      final created = DateTime.now();
      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-123',
        'sizeBytes': 1024,
        'createdData': created,
        'language': 'en',
        'format': 'pdf',
        'peerCount': 2,
        'isPinned': true,
        'lastHealthCheck': null,
      });

      final version = await db.getVersionByCid('cid-123');
      expect(version, isNotNull);
      expect(version!['cid'], equals('cid-123'));
      expect(version['manifestId'], equals(manifestId));
      expect(version['sizeBytes'], equals(1024));
      expect(version['format'], equals('pdf'));
      expect(version['createdData'], isA<DateTime>());
    });

    test('getVersionByCid returns null for missing cid', () async {
      final version = await db.getVersionByCid('missing-cid');
      expect(version, isNull);
    });

    test('getEndangeredVersions returns versions below threshold', () async {
      await db.insertManifest({
        'uuid': 'end-1',
        'title': 'Endangered',
        'lastUpdated': DateTime.now(),
      });
      final manifest = await db.getManifestByUuid('end-1');
      final manifestId = manifest!['id'] as int;

      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-low',
        'sizeBytes': 100,
        'createdData': DateTime.now(),
        'peerCount': 1,
      });
      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-ok',
        'sizeBytes': 100,
        'createdData': DateTime.now(),
        'peerCount': 5,
      });

      final endangered = await db.getEndangeredVersions(2);
      expect(endangered.length, equals(1));
      expect(endangered.single.cid, equals('cid-low'));
    });

    test('getVersionsForManifest returns only matching versions', () async {
      await db.insertManifest({
        'uuid': 'for-1',
        'title': 'Manifest Versions',
        'lastUpdated': DateTime.now(),
      });
      final manifest = await db.getManifestByUuid('for-1');
      final manifestId = manifest!['id'] as int;

      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-a',
        'sizeBytes': 1,
        'createdData': DateTime.now(),
      });
      await db.insertVersion({
        'manifestId': 9999,
        'cid': 'cid-other',
        'sizeBytes': 1,
        'createdData': DateTime.now(),
      });

      final versions = await db.getVersionsForManifest(manifestId);
      expect(versions.length, equals(1));
      expect(versions.single.cid, equals('cid-a'));
    });

    test('getUserActivityDates returns empty list', () async {
      final dates = await db.getUserActivityDates('did:alex:alice');
      expect(dates, isEmpty);
    });

    test('getProfileByPublicKey returns null when absent', () async {
      final profile = await db.getProfileByPublicKey('did:alex:bob');
      expect(profile, isNull);
    });

    test('databaseProvider provides an in-memory AppDatabase', () async {
      final container = ProviderContainer();
      final database = container.read(databaseProvider);
      expect(database, isA<AppDatabase>());
      await database.close();
      container.dispose();
    });

    test('insert and retrieve a user profile', () async {
      await db.into(db.userProfiles).insert(
            UserProfilesCompanion.insert(
              publicKey: 'did:alex:alice',
              lastActive: DateTime(2026, 1, 15),
            ),
          );

      final profile = await db.getProfileByPublicKey('did:alex:alice');
      expect(profile, isNotNull);
      expect(profile!.publicKey, 'did:alex:alice');
      expect(profile.reputation, 10);
    });

    test('insertVersion uses default values when omitted', () async {
      await db.insertManifest({
        'uuid': 'ver-defaults',
        'title': 'Version Defaults',
        'lastUpdated': DateTime.now(),
      });
      final manifest = await db.getManifestByUuid('ver-defaults');
      final manifestId = manifest!['id'] as int;

      await db.insertVersion({
        'manifestId': manifestId,
        'cid': 'cid-defaults',
        'sizeBytes': 100,
      });

      final version = await db.getVersionByCid('cid-defaults');
      expect(version, isNotNull);
      expect(version!['manifestId'], manifestId);
      expect(version['sizeBytes'], 100);
      expect(version['language'], 'en');
      expect(version['format'], 'bin');
      expect(version['peerCount'], 0);
      expect(version['isPinned'], isTrue);
      expect(version['createdData'], isA<DateTime>());
    });

    test('insertManifest uses default values when optional fields are omitted',
        () async {
      await db.insertManifest({
        'uuid': 'manifest-defaults',
        'title': 'Minimal',
        'lastUpdated': DateTime(2026, 1, 20),
      });

      final manifest = await db.getManifestByUuid('manifest-defaults');
      expect(manifest, isNotNull);
      expect(manifest!['category'], 'other');
      expect(manifest['isEncrypted'], isFalse);
      expect(manifest['author'], isNull);
    });

    test('getAllManifests maps nullable fields correctly', () async {
      await db.insertManifest({
        'uuid': 'map-fields',
        'title': 'Map Fields',
        'author': 'Author',
        'description': 'Description',
        'category': 'cat',
        'tags': 'a,b',
        'metadata': '{}',
        'isEncrypted': true,
        'encryptionKey': 'key',
        'lastUpdated': DateTime(2026, 1, 1),
      });

      final manifests = await db.getAllManifests();
      final match = manifests.firstWhere((m) => m.uuid == 'map-fields');
      expect(match.author, 'Author');
      expect(match.description, 'Description');
      expect(match.category, 'cat');
      expect(match.tags, 'a,b');
      expect(match.metadata, '{}');
      expect(match.isEncrypted, isTrue);
      expect(match.encryptionKey, 'key');
    });

    test('getVersionsForManifest returns empty for unknown manifest', () async {
      final versions = await db.getVersionsForManifest(999999);
      expect(versions, isEmpty);
    });

    test('credit transactions CRUD and query', () async {
      final now = DateTime.now();
      await db.insertCreditTransaction({
        'id': 'ctx_1',
        'timestamp': now,
        'type': 'storageReward',
        'amount': 50.0,
        'description': 'Daily storage reward',
        'hash': 'h123',
        'referenceId': 'ref_1',
        'isAttested': true,
      });

      final list = await db.getCreditTransactions(limit: 10);
      expect(list.length, 1);
      expect(list.first['id'], 'ctx_1');
      expect(list.first['amount'], 50.0);
      expect(list.first['isAttested'], isTrue);
    });

    test('daily minted tracking and upsert', () async {
      await db.upsertDailyMinted('2026-01-01', 'storageReward', 10.0);
      var daily = await db.getDailyMinted('2026-01-01');
      expect(daily['storageReward'], 10.0);

      await db.upsertDailyMinted('2026-01-01', 'storageReward', 25.0);
      daily = await db.getDailyMinted('2026-01-01');
      expect(daily['storageReward'], 25.0);
    });

    test('awarded DOIs tracking', () async {
      expect(await db.hasAwardedDoi('10.1038/s41586-020-2649-2'), isFalse);
      await db.insertAwardedDoi('10.1038/s41586-020-2649-2', cid: 'bafy_doi');
      expect(await db.hasAwardedDoi('10.1038/s41586-020-2649-2'), isTrue);
    });

    test('work receipt insertion, retrieval and marking spent', () async {
      await db.insertWorkReceipt({
        'receiptId': 'rcpt_001',
        'workType': 'por',
        'proverPubkey': 'pub_prover',
        'verifierPubkey': 'pub_verifier',
        'chunkIndices': '0,1,2',
        'challengeNonce': 'nonce123',
        'responseTag': 'tag456',
        'workUnits': 1.0,
        'amount': 10.0,
        'epoch': '2026-01-01',
        'expiresAt': 1767225600,
        'verifierSig': 'sig_ver',
      });

      final rcpt = await db.getWorkReceipt('rcpt_001');
      expect(rcpt, isNotNull);
      expect(rcpt!['receiptId'], 'rcpt_001');
      expect(rcpt['spent'], isFalse);

      await db.markReceiptSpent('rcpt_001');
      final updated = await db.getWorkReceipt('rcpt_001');
      expect(updated!['spent'], isTrue);

      expect(await db.getWorkReceipt('unknown'), isNull);
    });

    test('claimReceiptAtomically is a single-shot CAS', () async {
      await db.insertWorkReceipt({
        'receiptId': 'rcpt_cas',
        'workType': 'storage',
        'proverPubkey': 'p',
        'verifierPubkey': 'v',
        'chunkIndices': '[]',
        'challengeNonce': 'n',
        'responseTag': 't',
        'workUnits': 1.0,
        'amount': 5.0,
        'epoch': '2026-01-01',
        'expiresAt': 9999999999,
        'verifierSig': 'sig',
      });

      // First claim wins the CAS; every replay loses it.
      expect(await db.claimReceiptAtomically('rcpt_cas'), isTrue);
      expect(await db.claimReceiptAtomically('rcpt_cas'), isFalse);
      expect(await db.claimReceiptAtomically('rcpt_cas'), isFalse);
      // A receipt that was never persisted cannot be claimed.
      expect(await db.claimReceiptAtomically('rcpt_missing'), isFalse);

      final row = await db.getWorkReceipt('rcpt_cas');
      expect(row!['spent'], isTrue);
    });

    test('markReceiptSpent shares the conditional-update semantics',
        () async {
      await db.insertWorkReceipt({
        'receiptId': 'rcpt_legacy',
        'workType': 'storage',
        'proverPubkey': 'p',
        'verifierPubkey': 'v',
        'chunkIndices': '[]',
        'challengeNonce': 'n',
        'responseTag': 't',
        'workUnits': 1.0,
        'amount': 5.0,
        'epoch': '2026-01-01',
        'expiresAt': 9999999999,
        'verifierSig': 'sig',
        'spent': true,
      });
      // Legacy path on an already-spent row is a harmless no-op — it can
      // never resurrect a consumed receipt.
      await db.markReceiptSpent('rcpt_legacy');
      expect(await db.claimReceiptAtomically('rcpt_legacy'), isFalse);
    });

    test('ledger inserts deduplicate on primary-key collision', () async {
      Map<String, dynamic> tx(String id) => {
            'id': id,
            'timestamp': DateTime(2026, 1, 1),
            'type': 'storageReward',
            'amount': 10.0,
            'description': 'dedup test',
            'hash': 'h_$id',
          };
      await db.insertCreditTransaction(tx('dup_tx'));
      // Plain-insert would throw a PK violation here; insertOrIgnore
      // treats the duplicate as the expected dedup event.
      await db.insertCreditTransaction(tx('dup_tx'));
      final rows = await db.getCreditTransactions(limit: 10);
      expect(rows.where((r) => r['id'] == 'dup_tx').length, 1);

      Map<String, dynamic> receipt() => {
            'receiptId': 'dup_rcpt',
            'workType': 'storage',
            'proverPubkey': 'p',
            'verifierPubkey': 'v',
            'chunkIndices': '[]',
            'challengeNonce': 'n',
            'responseTag': 't',
            'workUnits': 1.0,
            'amount': 5.0,
            'epoch': '2026-01-01',
            'expiresAt': 9999999999,
            'verifierSig': 'sig',
          };
      await db.insertWorkReceipt(receipt());
      await db.insertWorkReceipt(receipt());
      expect(await db.getWorkReceipt('dup_rcpt'), isNotNull);

      await db.insertAwardedDoi('10.1/dup', cid: 'c1');
      await db.insertAwardedDoi('10.1/dup', cid: 'c2');
      expect(await db.hasAwardedDoi('10.1/dup'), isTrue);
    });

    test('insertAwardedDoi reports the atomic dedup result', () async {
      // First registration wins; the losing duplicate sees false — the
      // affected-rows signal closes the check-then-insert race window.
      expect(await db.insertAwardedDoi('10.1/race', cid: 'c1'), isTrue);
      expect(await db.insertAwardedDoi('10.1/race', cid: 'c2'), isFalse);
      expect(await db.hasAwardedDoi('10.1/race'), isTrue);
    });

    test('claimed_bounties is a durable claim CAS with release (REV3)',
        () async {
      expect(await db.isBountyClaimed('bounty_x'), isFalse);

      // First claim wins the PK compare-and-swap; replays lose it.
      expect(await db.insertClaimedBounty('bounty_x', 'bafk_x'), isTrue);
      expect(await db.insertClaimedBounty('bounty_x', 'bafk_x'), isFalse);
      expect(await db.isBountyClaimed('bounty_x'), isTrue);

      // A different bounty id is unaffected.
      expect(await db.insertClaimedBounty('bounty_y', 'bafk_y'), isTrue);
      expect(await db.isBountyClaimed('bounty_y'), isTrue);

      // delete releases a failed claim — the id is claimable again.
      await db.deleteClaimedBounty('bounty_x');
      expect(await db.isBountyClaimed('bounty_x'), isFalse);
      expect(await db.insertClaimedBounty('bounty_x', 'bafk_x'), isTrue);
      // Deleting an absent id is a harmless no-op.
      await db.deleteClaimedBounty('bounty_missing');
    });

    test('getLedgerBalanceSum nets credits and debits over all rows',
        () async {
      expect(await db.getLedgerBalanceSum(), 0.0);
      Future<void> tx(String id, double amount) =>
          db.insertCreditTransaction({
            'id': id,
            'timestamp': DateTime(2026, 1, 1),
            'type': 'storageReward',
            'amount': amount,
            'description': 'sum test',
            'hash': 'h_$id',
          });
      await tx('s1', 100.0);
      await tx('s2', 50.0);
      await tx('s3', -30.0);
      expect(await db.getLedgerBalanceSum(), 120.0);
    });

    test('hasGenesisTransaction matches id and legacy description marker',
        () async {
      expect(await db.hasGenesisTransaction(), isFalse);

      // Legacy builds wrote genesis under a random id — the description
      // marker still identifies it.
      await db.insertCreditTransaction({
        'id': 'tx_random_old',
        'timestamp': DateTime(2024, 1, 1),
        'type': 'verificationReward',
        'amount': 100.0,
        'description': 'Genesis Common Heritage Welcome Allocation',
        'hash': 'h1',
      });
      expect(await db.hasGenesisTransaction(), isTrue);

      // And the deterministic modern id matches too (fresh db).
      final db2 = AppDatabase();
      addTearDown(db2.close);
      expect(await db2.hasGenesisTransaction(), isFalse);
      await db2.insertCreditTransaction({
        'id': 'tx_genesis',
        'timestamp': DateTime(2024, 1, 1),
        'type': 'verificationReward',
        'amount': 100.0,
        'description': 'whatever',
        'hash': 'h2',
      });
      expect(await db2.hasGenesisTransaction(), isTrue);
    });

    test('user profiles, activity dates and endangered versions', () async {
      expect(await db.getUserActivityDates('pubkey_1'), isEmpty);
      expect(await db.getProfileByPublicKey('pubkey_missing'), isNull);

      final endangered = await db.getEndangeredVersions(5);
      expect(endangered, isA<List<ContentVersion>>());
    });



    test('migration strategy executes onUpgrade logic', () async {
      final strategy = db.migration;
      final calledTables = <String>[];
      final calledColumns = <String>[];

      // Custom test migrator tracking invocations
      final fakeMigrator = _FakeMigrator(
        onAddCol: (tbl, col) => calledColumns.add('${tbl.entityName}.${col.$name}'),
        onCreateTbl: (tbl) => calledTables.add(tbl.entityName),
      );

      // v1→v5: the three v2 content_versions columns, the four v3
      // tables, the v4 work_receipts.v column, and the v5
      // claimed_bounties table. (onUpgrade keys off `from` alone.)
      await strategy.onUpgrade(fakeMigrator, 1, 5);
      expect(calledColumns.length, equals(4));
      expect(calledColumns, contains('work_receipts.v'));
      expect(calledTables.length, equals(5));
      expect(calledTables, contains('claimed_bounties'));

      calledColumns.clear();
      calledTables.clear();

      await strategy.onUpgrade(fakeMigrator, 2, 5);
      expect(calledColumns, equals(['work_receipts.v']));
      expect(calledTables.length, equals(5));

      calledColumns.clear();
      calledTables.clear();

      // The v3→v5 step adds the receipt wire-version column AND the
      // v5 claimed_bounties table.
      await strategy.onUpgrade(fakeMigrator, 3, 5);
      expect(calledColumns, equals(['work_receipts.v']));
      expect(calledTables, equals(['claimed_bounties']));

      calledColumns.clear();
      calledTables.clear();

      // The v4→v5 step creates ONLY the durable bounty-claim ledger.
      await strategy.onUpgrade(fakeMigrator, 4, 5);
      expect(calledColumns, isEmpty);
      expect(calledTables, equals(['claimed_bounties']));
    });

    test('work_receipts.v round-trips and defaults to the legacy scheme',
        () async {
      Map<String, dynamic> row(String id) => {
            'receiptId': id,
            'workType': 'storage',
            'proverPubkey': 'p',
            'verifierPubkey': 'v',
            'chunkIndices': '[]',
            'challengeNonce': 'n',
            'responseTag': 't',
            'workUnits': 1.0,
            'amount': 5.0,
            'epoch': '2026-01-01',
            'expiresAt': 9999999999,
            'verifierSig': 'sig',
          };

      // Omitted -> the legacy v1 scheme (pre-domain signatures).
      await db.insertWorkReceipt(row('rcpt_legacy'));
      expect((await db.getWorkReceipt('rcpt_legacy'))!['v'], 1);

      // Explicit v2 (domain-separated) round-trips.
      await db.insertWorkReceipt({...row('rcpt_v2'), 'v': 2});
      expect((await db.getWorkReceipt('rcpt_v2'))!['v'], 2);

      // An unknown FUTURE version is still representable — the declared
      // v is stored verbatim, never clamped.
      await db.insertWorkReceipt({...row('rcpt_v9'), 'v': 9});
      expect((await db.getWorkReceipt('rcpt_v9'))!['v'], 9);
    });

    test('v3→v4 migration preserves work_receipts rows and defaults v=1',
        () async {
      // Simulate a real v3 database: rebuild work_receipts WITHOUT the v
      // column and insert a legacy row the way a v3 build would have.
      await db.customStatement('DROP TABLE work_receipts');
      await db.customStatement('''
        CREATE TABLE work_receipts (
          receipt_id TEXT NOT NULL PRIMARY KEY,
          work_type TEXT NOT NULL,
          prover_pubkey TEXT NOT NULL,
          verifier_pubkey TEXT NOT NULL,
          cid TEXT,
          chunk_indices TEXT NOT NULL,
          challenge_nonce TEXT NOT NULL,
          response_tag TEXT NOT NULL,
          work_units REAL NOT NULL,
          amount REAL NOT NULL,
          epoch TEXT NOT NULL,
          expires_at INTEGER NOT NULL,
          evidence_hash TEXT,
          verifier_sig TEXT NOT NULL,
          prover_sig TEXT,
          spent INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.customStatement(
        'INSERT INTO work_receipts (receipt_id, work_type, prover_pubkey, '
        'verifier_pubkey, chunk_indices, challenge_nonce, response_tag, '
        'work_units, amount, epoch, expires_at, verifier_sig, spent, '
        "created_at) VALUES ('legacy_rcpt', 'storage', 'p_v3', 'v_v3', "
        "'[]', 'nonce', 'tag', 2.0, 7.5, '2026-01-01', 9999999999, "
        "'sig_v3', 0, 1700000000)",
      );

      // The real migration path — a Migrator bound to this database, so
      // the ALTER TABLE actually executes.
      await db.migration.onUpgrade(db.createMigrator(), 3, 4);

      final row = await db.getWorkReceipt('legacy_rcpt');
      expect(row, isNotNull, reason: 'migration must preserve the row');
      expect(row!['v'], 1,
          reason: 'pre-v4 rows hydrate as the legacy bare-domain scheme');
      expect(row['verifierSig'], 'sig_v3');
      expect(row['amount'], 7.5);
      expect(row['spent'], isFalse);
      // And the upgraded table accepts new v2 writes.
      await db.insertWorkReceipt({
        'receiptId': 'post_mig',
        'v': 2,
        'workType': 'storage',
        'proverPubkey': 'p',
        'verifierPubkey': 'v',
        'chunkIndices': '[]',
        'challengeNonce': 'n',
        'responseTag': 't',
        'workUnits': 1.0,
        'amount': 5.0,
        'epoch': '2026-01-01',
        'expiresAt': 9999999999,
        'verifierSig': 'sig',
      });
      expect((await db.getWorkReceipt('post_mig'))!['v'], 2);
    });
  });
}

class _FakeMigrator extends Migrator {
  final void Function(TableInfo, GeneratedColumn) onAddCol;
  final void Function(TableInfo) onCreateTbl;

  _FakeMigrator({required this.onAddCol, required this.onCreateTbl})
      : super(AppDatabase(NativeDatabase.memory()));

  @override
  Future<void> addColumn(TableInfo table, GeneratedColumn column) async {
    onAddCol(table, column);
  }

  @override
  Future<void> createTable(TableInfo table) async {
    onCreateTbl(table);
  }
}

