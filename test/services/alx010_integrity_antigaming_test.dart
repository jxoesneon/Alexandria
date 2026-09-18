import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeSecureStorage implements SecureStorageService {
  @override
  String get keyPrefix => '';
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);

  @override
  Future<void> deleteAll() async => _data.clear();

  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

class _FakeAuditLogService extends AuditLogService {
  _FakeAuditLogService(super.ref);

  @override
  Future<void> log(String action,
      {String? details, String? actor, String status = 'Success'}) async {}
}

/// IPFS stub that can corrupt a stored payload after ingest - simulating a
/// malicious or bit-rotted peer serving altered bytes for a valid CID.
class _CorruptibleIpfs extends IpfsService {
  _CorruptibleIpfs(super.ref);

  final Map<String, Uint8List> store = {};

  @override
  Future<String> addFile(Uint8List data) async {
    final cid = CidService().computeCid(data).toBase32();
    store[cid] = data;
    return cid;
  }

  @override
  Stream<Uint8List> getFile(String cid) async* {
    yield store[cid] ?? Uint8List(0);
  }

  void corrupt(String cid) {
    final bytes = store[cid];
    if (bytes == null || bytes.isEmpty) return;
    bytes[0] = bytes[0] ^ 0xFF;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late _CorruptibleIpfs ipfs;
  late ContentRepository repo;

  setUp(() {
    db = AppDatabase();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      ipfsServiceProvider.overrideWith((ref) {
        ipfs = _CorruptibleIpfs(ref);
        return ipfs;
      }),
      secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
      auditLogServiceProvider.overrideWith((ref) => _FakeAuditLogService(ref)),
    ]);
    repo = container.read(contentRepositoryProvider);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Uint8List payloadOf(String text) => Uint8List.fromList(utf8.encode(text));

  Future<String> seedManifest() => repo.createContent(
        title: 'Integrity Test Work',
        fileData: payloadOf('A' * 512),
        format: 'md',
      );

  group('CID payload verification (ALX-010 §1)', () {
    test('computeCid → decodeDigest round-trips', () {
      final cidService = CidService();
      final data = payloadOf('hello alexandria');
      final cid = cidService.computeCid(data);
      final decoded = cidService.decodeDigest(cid.toBase32());
      expect(decoded, isNotNull);
      expect(decoded!.length, 32);
      expect(cidService.verifyContent(cid.toBase32(), data), isTrue);
    });

    test('verifyContent rejects tampered bytes and garbage CIDs', () {
      final cidService = CidService();
      final data = payloadOf('original bytes');
      final cid = cidService.computeCid(data).toBase32();
      expect(cidService.verifyContent(cid, payloadOf('forged bytes')), isFalse);
      expect(cidService.verifyContent('not-a-cid', data), isFalse);
      expect(
          cidService.verifyContent(
              'QmFake0fake0fake0fake0fake0fake0fake0fake0fake0fak', data),
          isFalse);
    });

    test('retrieveContent throws when a peer serves mismatched bytes',
        () async {
      final uuid = await seedManifest();
      final manifest = await repo.getManifestByUuid(uuid);
      final versions = await db.getVersionsForManifest(manifest!.id);
      final cid = versions.first.cid;

      // Untampered retrieval succeeds
      final ok = await repo.retrieveContent(cid);
      expect(ok.length, 512);

      // Corrupt the stored payload - retrieval must refuse it
      ipfs.corrupt(cid);
      await expectLater(
        repo.retrieveContent(cid),
        throwsA(isA<StateError>()),
      );
    });

    test('probeContentIntegrity reports computed state for Safe Harbor',
        () async {
      await container.read(identityServiceProvider).generateIdentity();
      final uuid = await seedManifest();
      final manifest = await repo.getManifestByUuid(uuid);
      final v = (await db.getVersionsForManifest(manifest!.id)).first;

      final report = await repo.probeContentIntegrity(v.cid);
      expect(report.payloadHashOk, isTrue);
      expect(report.signatureValid, isTrue);
      expect(report.flaggedReason, isNull);
      expect(report.publisherPubkey, isNotNull);

      // Corrupted payload → hash check reports false (never asserts OK)
      ipfs.corrupt(v.cid);
      final bad = await repo.probeContentIntegrity(v.cid);
      expect(bad.payloadHashOk, isFalse);
      // Signature over the CID binding still verifies - the binding is
      // intact even though the stored bytes are not.
      expect(bad.signatureValid, isTrue);
    });
  });

  group('Signed version records (ALX-010 §2)', () {
    test('createContent signs the version record with node identity', () async {
      await container.read(identityServiceProvider).generateIdentity();
      final uuid = await seedManifest();
      final manifest = await repo.getManifestByUuid(uuid);
      final v = (await db.getVersionsForManifest(manifest!.id)).first;

      expect(v.publisherPubkey, isNotNull);
      expect(v.signature, isNotNull);

      final valid = await repo.verifyVersionSignature(
        manifestUuid: uuid,
        cid: v.cid,
        publisherPubkey: v.publisherPubkey,
        signature: v.signature,
      );
      expect(valid, isTrue);
    });

    test('signature verification fails for tampered CID bindings', () async {
      await container.read(identityServiceProvider).generateIdentity();
      final uuid = await seedManifest();
      final manifest = await repo.getManifestByUuid(uuid);
      final v = (await db.getVersionsForManifest(manifest!.id)).first;

      // Same signature, different CID → invalid
      final other = await repo.addContentVersion(
        manifestUuid: uuid,
        fileData: payloadOf('B' * 512),
        format: 'md-brief',
      );
      expect(
        await repo.verifyVersionSignature(
          manifestUuid: uuid,
          cid: other,
          publisherPubkey: v.publisherPubkey,
          signature: v.signature,
        ),
        isFalse,
      );
    });

    test('unsigned legacy records verify as false, not true', () async {
      // No identity generated → record is unsigned
      final uuid = await seedManifest();
      final manifest = await repo.getManifestByUuid(uuid);
      final v = (await db.getVersionsForManifest(manifest!.id)).first;

      expect(v.signature, isNull);
      expect(
        await repo.verifyVersionSignature(
          manifestUuid: uuid,
          cid: v.cid,
          publisherPubkey: v.publisherPubkey,
          signature: v.signature,
        ),
        isFalse,
      );
    });
  });

  group('Version hygiene gates (ALX-010 §8)', () {
    test('rejects payloads below the 64-byte floor', () async {
      final uuid = await seedManifest();
      await expectLater(
        repo.addContentVersion(
          manifestUuid: uuid,
          fileData: payloadOf('tiny'),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('caps versions per manifest at 20', () async {
      final uuid = await seedManifest();
      for (var i = 0; i < ContentRepository.maxVersionsPerManifest - 1; i++) {
        await repo.addContentVersion(
          manifestUuid: uuid,
          fileData: payloadOf('edition-$i-${'x' * 100}'),
        );
      }
      await expectLater(
        repo.addContentVersion(
          manifestUuid: uuid,
          fileData: payloadOf('one-too-many-${'x' * 100}'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('flags fragment payloads instead of rejecting them', () async {
      final uuid = await seedManifest();
      final manifest = await repo.getManifestByUuid(uuid);
      final original = (await db.getVersionsForManifest(manifest!.id)).first;
      final originalBytes = ipfs.store[original.cid]!;

      // Split attack: submit the first 200 bytes of the real edition
      final fragment = Uint8List.fromList(originalBytes.sublist(0, 200));
      await repo.addContentVersion(
        manifestUuid: uuid,
        fileData: fragment,
      );

      final versions = await db.getVersionsForManifest(manifest.id);
      final flagged = versions.firstWhere((v) => v.cid != original.cid);
      expect(flagged.flaggedReason, 'suspect-fragment-of:${original.cid}');
    });
  });

  group('Credit mint caps & rarity attestation (ALX-010 §3-5)', () {
    late CreditService credits;

    setUp(() {
      credits = CreditService(initialBalance: 0.0);
    });

    test('unattested rarity is clamped to 1.0x regardless of peerCount', () {
      expect(
        CreditService.rarityWeightFor(1, rarityAttested: false),
        1.0,
      );
      expect(
        CreditService.rarityWeightFor(0, rarityAttested: false),
        1.0,
      );
    });

    test('attested rarity unlocks the rarity ladder', () {
      expect(CreditService.rarityWeightFor(1, rarityAttested: true), 5.0);
      expect(CreditService.rarityWeightFor(2, rarityAttested: true), 3.0);
      expect(CreditService.rarityWeightFor(4, rarityAttested: true), 1.5);
      expect(CreditService.rarityWeightFor(10, rarityAttested: true), 1.0);
    });

    test('daily storage mint cap is enforced', () {
      var minted = 0.0;
      // Each call at max size would mint 50.0 - 5 calls = 250 > 200 cap
      for (var i = 0; i < 5; i++) {
        minted += credits.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 10,
          porPassed: true,
          cid: 'bafk_cap_test_$i',
        );
      }
      expect(minted, 200.0);
      // Sixth call mints nothing
      expect(
        credits.awardStorageCredits(
          sizeBytes: 500 * 1024 * 1024,
          peerCount: 10,
          porPassed: true,
          cid: 'bafk_cap_test_extra',
        ),
        0.0,
      );
    });

    test('verification mint cap is enforced independently', () {
      var minted = 0.0;
      for (var i = 0; i < 40; i++) {
        minted += credits.awardVerificationCredits(
          action: 'spam-verification-$i',
          targetId: 'target-$i',
          amount: 10.0,
        );
      }
      expect(minted, 100.0);
    });

    test('PoR failure penalty still applies under cap', () {
      final result = credits.awardStorageCredits(
        sizeBytes: 1024,
        peerCount: 1,
        porPassed: false,
        cid: 'bafk_penalty',
      );
      expect(result, -5.0);
      expect(credits.balance, 0.0); // clamped, never negative
    });
  });
}
