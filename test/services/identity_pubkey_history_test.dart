// Safety item 3 - IdentityService's append-only local-pubkey history.
// Rotation (importIdentity / generateIdentity) must accrete every key
// ever installed so a receipt signed by a RETIRED key stays
// self-issued forever. Scaffolding mirrors identity_service_test.dart.
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeSecureStorage implements SecureStorageService {
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

String _hexEncode(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<Uint8List> _newSeed() async {
  final kp = await Ed25519().newKeyPair();
  return Uint8List.fromList(await kp.extractPrivateKeyBytes());
}

void main() {
  group('IdentityService knownLocalPubkeyHexes (Safety item 3)', () {
    late _FakeSecureStorage storage;
    late IdentityService service;

    setUp(() {
      storage = _FakeSecureStorage();
      service = IdentityService(storage);
    });

    tearDown(() async {
      await service.dispose();
    });

    test('empty before any identity exists', () async {
      expect(await service.knownLocalPubkeyHexes(), isEmpty);
    });

    test('generateIdentity records the new pubkey', () async {
      final identity = await service.generateIdentity();
      expect(await service.knownLocalPubkeyHexes(),
          {_hexEncode(identity.publicKey)});
    });

    test('rotation accretes: generate → import keeps BOTH keys', () async {
      final first = await service.generateIdentity();
      final seedB = await _newSeed();
      final second = await service.importIdentity(seedB);
      expect(second.publicKey, isNot(equals(first.publicKey)));

      final known = await service.knownLocalPubkeyHexes();
      expect(
          known,
          containsAll(
              {_hexEncode(first.publicKey), _hexEncode(second.publicKey)}));
      expect(known.length, 2);
    });

    test('re-importing the SAME key does not duplicate the entry', () async {
      final seed = await _newSeed();
      final first = await service.importIdentity(seed);
      await service.importIdentity(seed); // recovery of the same key
      expect(
          await service.knownLocalPubkeyHexes(), {_hexEncode(first.publicKey)});
    });

    test(
        'history survives deleteIdentity — a deleted key stays '
        'self-vouched forever', () async {
      final first = await service.generateIdentity();
      final second = await service.generateIdentity();
      await service.deleteIdentity();

      expect(await service.getIdentity(), isNull);
      expect(
          await service.knownLocalPubkeyHexes(),
          containsAll(
              {_hexEncode(first.publicKey), _hexEncode(second.publicKey)}));
    });

    test(
        'history persists across service instances on one store '
        '(restart durability)', () async {
      final first = await service.generateIdentity();
      final second = await service.generateIdentity();

      final restarted = IdentityService(storage);
      addTearDown(restarted.dispose);
      expect(
          await restarted.knownLocalPubkeyHexes(),
          containsAll(
              {_hexEncode(first.publicKey), _hexEncode(second.publicKey)}));
    });

    test(
        'legacy install (pre-feature keys, no history blob) still '
        'reports the current key — the current-key floor', () async {
      // Write a coherent pair out-of-band, as a pre-feature build would
      // have persisted it.
      final keyPair = await Ed25519().newKeyPair();
      final pub = Uint8List.fromList((await keyPair.extractPublicKey()).bytes);
      final seed = Uint8List.fromList(await keyPair.extractPrivateKeyBytes());
      await storage.write('alexandria_identity_private_key', _hexEncode(seed));
      await storage.write('alexandria_identity_public_key', _hexEncode(pub));
      await storage.write(
          'alexandria_identity_created', DateTime.now().toIso8601String());

      // Even before any read/heal, the resolver includes the current key.
      expect(await service.knownLocalPubkeyHexes(), contains(_hexEncode(pub)));

      // And the first served read backfills the history blob so the key
      // stays known after a later rotation.
      expect(await service.getIdentity(), isNotNull);
      final seedB = await _newSeed();
      final rotated = await service.importIdentity(seedB);
      final known = await service.knownLocalPubkeyHexes();
      expect(
          known, containsAll({_hexEncode(pub), _hexEncode(rotated.publicKey)}),
          reason: 'the legacy key must be recorded before rotation, so '
              'a receipt it signed is still self-issued');
    });

    test('a corrupt history blob degrades to the current-key floor', () async {
      final identity = await service.generateIdentity();
      await storage.write('alexandria_identity_pubkey_history', 'not-json{{[');
      expect(await service.knownLocalPubkeyHexes(),
          {_hexEncode(identity.publicKey)});
    });

    test('history entries are canonical lowercase hex', () async {
      final identity = await service.generateIdentity();
      final known = await service.knownLocalPubkeyHexes();
      expect(known.single, _hexEncode(identity.publicKey));
      expect(known.single, equals(known.single.toLowerCase()));
    });
  });
}
