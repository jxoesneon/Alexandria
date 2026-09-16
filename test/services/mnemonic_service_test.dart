import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/providers/security_providers.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/mnemonic_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _MockIdentityService implements IdentityService {
  AlexandriaIdentity? identity;

  /// The store the delegated backup-marker write lands in — mirrors
  /// [IdentityService.markMnemonicBackupConfirmed] writing into the
  /// shared SecureStorageService.
  SecureStorageService? markerStore;
  int markBackupCalls = 0;
  String? lastPhraseHash;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => identity;

  @override
  Future<void> markMnemonicBackupConfirmed(
    String phraseHash, {
    String? expectedPublicKeyHex,
  }) async {
    markBackupCalls++;
    lastPhraseHash = phraseHash;
    await markerStore?.write(SecureStorageKeys.mnemonicBackup, phraseHash);
  }

  /// Mirrors the real [IdentityService.importIdentity]: derives the
  /// keypair from the seed and makes it the current identity.
  @override
  Future<AlexandriaIdentity> importIdentity(
    Uint8List privateKeySeed,
  ) async {
    final keyPair = await Ed25519().newKeyPairFromSeed(privateKeySeed);
    final publicKey = await keyPair.extractPublicKey();
    identity = AlexandriaIdentity(
      publicKey: Uint8List.fromList(publicKey.bytes),
      privateKey: privateKeySeed,
      createdAt: DateTime.now(),
    );
    return identity!;
  }

  /// Wired to `onIdentityRecovered` by mnemonicServiceProvider — must
  /// exist as a real member or the provider's tear-off hits
  /// noSuchMethod and throws.
  @override
  Future<void> reloadIdentity() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory [SecureStorageService] so a REAL [IdentityService] (and
/// its cache) can be exercised end-to-end in tests.
class _InMemorySecureStorage implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deleteAll() async => data.clear();

  @override
  Future<bool> containsKey(String key) async => data.containsKey(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MnemonicService Tests', () {
    late _MockIdentityService fakeIdentity;
    late MnemonicService mnemonicService;

    late _InMemorySecureStorage storage;

    setUp(() {
      fakeIdentity = _MockIdentityService();
      storage = _InMemorySecureStorage();
      fakeIdentity.markerStore = storage;
      mnemonicService = MnemonicService(fakeIdentity, storage: storage);
    });

    test('generates valid 24-word mnemonic phrase', () async {
      final result = await mnemonicService.generateMnemonic();
      expect(result.words.length, equals(24));
      expect(result.phrase.split(' ').length, equals(24));
      expect(result.entropy.length, equals(32));
      expect(result.seed.length, equals(64));

      final isValid = mnemonicService.validateMnemonic(result.words);
      expect(isValid, isTrue);
    });

    test('validates incorrect or corrupt mnemonic words', () {
      expect(mnemonicService.validateMnemonic([]), isFalse);
      expect(mnemonicService.validateMnemonic(List.filled(23, 'abandon')),
          isFalse);
      expect(mnemonicService.validateMnemonic(List.filled(25, 'abandon')),
          isFalse);

      // 24 invalid words not in wordlist
      final invalidWords = List.filled(24, 'notawordxyz');
      expect(mnemonicService.validateMnemonic(invalidWords), isFalse);

      // 24 valid words with invalid checksum
      final corruptChecksum = List.filled(24, 'abandon');
      // For BIP-39, 24 'abandon' words has a specific checksum; let's verify validateMnemonic behavior
      final isValid = mnemonicService.validateMnemonic(corruptChecksum);
      expect(isValid, isA<bool>());
    });

    test('recovers identity from a valid generated mnemonic', () async {
      final generated = await mnemonicService.generateMnemonic();
      final recovered =
          await mnemonicService.recoverFromMnemonic(generated.words);

      expect(recovered, isNotNull);
      expect(recovered!.publicKey, isNotEmpty);
      expect(recovered.privateKey, isNotEmpty);
      expect(recovered.privateKey.length, equals(32));
    });

    test('recoverFromMnemonic returns null for invalid mnemonic', () async {
      final recovered = await mnemonicService
          .recoverFromMnemonic(['invalid', 'words', 'list']);
      expect(recovered, isNull);
    });

    test('validateMnemonic accepts the canonical BIP-39 zero-entropy vector',
        () {
      // Official BIP-39 test vector: 32 zero bytes of entropy encodes to
      // 23x 'abandon' + 'art' (last word carries the checksum bits).
      final words = [...List.filled(23, 'abandon'), 'art'];
      expect(mnemonicService.validateMnemonic(words), isTrue);
    });

    test('validateMnemonic rejects synthetic and bad-checksum phrases', () {
      // Synthetic filler words like the old 'w0'..'wN' padding hack
      expect(
        mnemonicService.validateMnemonic(List.filled(24, 'w0')),
        isFalse,
      );
      // Real words, bad checksum: 24x 'abandon' is not a valid phrase
      expect(
        mnemonicService.validateMnemonic(List.filled(24, 'abandon')),
        isFalse,
      );
    });

    test('backup -> recover round-trips the SAME public key', () async {
      final algo = Ed25519();
      final kp = await algo.newKeyPair();
      final pub = await kp.extractPublicKey();
      final seed = Uint8List.fromList(await kp.extractPrivateKeyBytes());

      fakeIdentity.identity = AlexandriaIdentity(
        publicKey: Uint8List.fromList(pub.bytes),
        privateKey: seed,
        createdAt: DateTime.now(),
      );

      final backup = await mnemonicService.backupCurrentIdentity();
      expect(backup, isNotNull);
      expect(backup!.words.length, equals(24));
      // The phrase encodes the identity's OWN key as entropy
      expect(backup.entropy, equals(seed));
      expect(mnemonicService.validateMnemonic(backup.words), isTrue);

      final recovered = await mnemonicService.recoverFromMnemonic(backup.words);
      expect(recovered, isNotNull);
      expect(recovered!.publicKey, equals(Uint8List.fromList(pub.bytes)));
      expect(recovered.privateKey, equals(seed));
    });

    test('backupCurrentIdentity and hasBackup lifecycle', () async {
      // When no identity exists
      fakeIdentity.identity = null;
      var backup = await mnemonicService.backupCurrentIdentity();
      expect(backup, isNull);

      // With an identity
      fakeIdentity.identity = AlexandriaIdentity(
        publicKey: Uint8List.fromList(List.filled(32, 1)),
        privateKey: Uint8List.fromList(List.filled(32, 2)),
        createdAt: DateTime.now(),
      );

      backup = await mnemonicService.backupCurrentIdentity();
      expect(backup, isNotNull);
      expect(backup!.words.length, equals(24));

      // Deriving/displaying the phrase does NOT mark the backup as
      // done — the marker is written on explicit user confirmation.
      expect(await mnemonicService.hasBackup(), isFalse);
      expect(
        storage.data.containsKey('alexandria_mnemonic_backup'),
        isFalse,
      );

      await mnemonicService.markBackupConfirmed(backup.phrase);
      expect(await mnemonicService.hasBackup(), isTrue);
      // Single key, single store: the marker lives in the shared
      // SecureStorageService under 'alexandria_mnemonic_backup'.
      expect(storage.data['alexandria_mnemonic_backup'], isNotNull);
      expect(
        storage.data.containsKey('alexandria_mnemonic_backup_hash'),
        isFalse,
      );
    });

    test('recoverFromMnemonic invokes onIdentityRecovered on success only',
        () async {
      var callCount = 0;
      final service = MnemonicService(
        fakeIdentity,
        storage: _InMemorySecureStorage(),
        onIdentityRecovered: () async => callCount++,
      );

      final generated = await service.generateMnemonic();
      final recovered = await service.recoverFromMnemonic(generated.words);
      expect(recovered, isNotNull);
      expect(callCount, equals(1));

      // A rejected phrase must not fire the hook.
      await service.recoverFromMnemonic(const ['bad', 'phrase']);
      expect(callCount, equals(1));
    });

    test('onboarding backup phrase recovers the SAME identity (round-trip)',
        () async {
      // Mirrors the onboarding flow end-to-end with REAL services:
      // identityService.generateIdentity() runs first, then the phrase
      // shown by _generateMnemonic() comes from backupCurrentIdentity()
      // (derived from the stored key), and recoverFromMnemonic() must
      // restore the SAME keypair. The old bug called generateMnemonic()
      // — fresh random entropy — so the "backup" recovered a different
      // identity (decoy phrase).
      final storage = _InMemorySecureStorage();
      final identityService = IdentityService(storage);
      final service = MnemonicService(
        identityService,
        storage: storage,
        onIdentityRecovered: identityService.reloadIdentity,
      );

      final created = await identityService.generateIdentity();

      final backup = await service.backupCurrentIdentity();
      expect(backup, isNotNull);
      expect(backup!.words.length, equals(24));
      expect(service.validateMnemonic(backup.words), isTrue);

      final recovered = await service.recoverFromMnemonic(backup.words);
      expect(recovered, isNotNull);
      expect(recovered!.publicKey, equals(created.publicKey));
      expect(recovered.privateKey, equals(created.privateKey));

      final current = await identityService.getIdentity();
      expect(current!.publicKey, equals(created.publicKey));
    });

    test('recovering while another identity is cached serves the NEW key',
        () async {
      // Regression for the split-brain: recoverFromMnemonic used to
      // write the storage keys directly and never clear
      // IdentityService._cachedIdentity, so getIdentity() kept serving
      // the OLD keypair after a recovery.
      final storage = _InMemorySecureStorage();
      final identityService = IdentityService(storage);
      final service = MnemonicService(
        identityService,
        storage: storage,
        onIdentityRecovered: identityService.reloadIdentity,
      );

      // Identity A: created and cached by IdentityService.
      final identityA = await identityService.generateIdentity();
      expect(
        (await identityService.getIdentity())!.publicKey,
        equals(identityA.publicKey),
      );

      // Identity B: an unrelated keypair with a real backup phrase.
      final storageB = _InMemorySecureStorage();
      final identityServiceB = IdentityService(storageB);
      final serviceB = MnemonicService(identityServiceB, storage: storageB);
      final keyPairB = await Ed25519().newKeyPair();
      final publicKeyB = await keyPairB.extractPublicKey();
      await identityServiceB.importIdentity(
        Uint8List.fromList(await keyPairB.extractPrivateKeyBytes()),
      );
      final backupB = await serviceB.backupCurrentIdentity();
      expect(backupB, isNotNull);

      // Recover B while A is still cached.
      final recovered = await service.recoverFromMnemonic(backupB!.words);
      expect(recovered, isNotNull);
      expect(
        recovered!.publicKey,
        equals(Uint8List.fromList(publicKeyB.bytes)),
      );

      // getIdentity() must now return B — never the stale A.
      final current = await identityService.getIdentity();
      expect(current, isNotNull);
      expect(current!.publicKey, equals(recovered.publicKey));
      expect(current.publicKey, isNot(equals(identityA.publicKey)));
      expect(current.privateKey, equals(recovered.privateKey));
    });

    test('recoverFromMnemonic still succeeds when onIdentityRecovered throws',
        () async {
      // The hook is cache coherency belt-and-suspenders — a failure in
      // it must not turn a persisted recovery into a reported failure.
      final service = MnemonicService(
        fakeIdentity,
        storage: _InMemorySecureStorage(),
        onIdentityRecovered: () async => throw StateError('hook blew up'),
      );

      final generated = await service.generateMnemonic();
      final recovered = await service.recoverFromMnemonic(generated.words);
      expect(recovered, isNotNull);
      expect(recovered!.publicKey, isNotEmpty);
    });

    test('backup marker is cleared when the identity is replaced', () async {
      // Single-key single-store: the marker is written by
      // markBackupConfirmed into the shared SecureStorageService and
      // cleared by IdentityService whenever the stored pubkey changes.
      final storage = _InMemorySecureStorage();
      final identityService = IdentityService(storage);
      final service = MnemonicService(identityService, storage: storage);

      final created = await identityService.generateIdentity();
      final backup = await service.backupCurrentIdentity();
      await service.markBackupConfirmed(backup!.phrase);
      expect(await service.hasBackup(), isTrue);

      // Re-importing the SAME key keeps the marker — the old phrase
      // still recovers this identity.
      await identityService.importIdentity(
        Uint8List.fromList(created.privateKey),
      );
      expect(await service.hasBackup(), isTrue);

      // Replacing the keypair clears it — the old phrase can no longer
      // recover the current identity.
      final otherKeyPair = await Ed25519().newKeyPair();
      await identityService.importIdentity(
        Uint8List.fromList(await otherKeyPair.extractPrivateKeyBytes()),
      );
      expect(await service.hasBackup(), isFalse);
      expect(
        storage.data.containsKey('alexandria_mnemonic_backup'),
        isFalse,
      );

      // Same for generating a fresh keypair and for deletion.
      await service.markBackupConfirmed('some phrase');
      await identityService.generateIdentity();
      expect(await service.hasBackup(), isFalse);

      await service.markBackupConfirmed('some phrase');
      await identityService.deleteIdentity();
      expect(await service.hasBackup(), isFalse);
    });

    test(
        'markBackupConfirmed races an import — no stale marker '
        'survives on the new identity', () async {
      // The marker write is delegated into IdentityService's
      // serialized op-chain AND carries the public key the phrase
      // recovers. Whichever serialized order the two ops land in, a
      // confirmation for the OLD key's phrase must never leave
      // hasBackup()==true on the NEW identity.
      final storage = _InMemorySecureStorage();
      final identityService = IdentityService(storage);
      final service = MnemonicService(identityService, storage: storage);

      final identityA = await identityService.generateIdentity();
      final backupA = await service.backupCurrentIdentity();
      expect(backupA, isNotNull);

      final keyPairB = await Ed25519().newKeyPair();
      final seedB = Uint8List.fromList(await keyPairB.extractPrivateKeyBytes());
      final publicKeyB =
          Uint8List.fromList((await keyPairB.extractPublicKey()).bytes);
      expect(publicKeyB, isNot(equals(identityA.publicKey)));

      // Order A: confirmation is ISSUED before the import — if its
      // serialized op runs first it writes, then the import's
      // pubkey-change clears it; if it runs second, the staleness
      // check drops it.
      await Future.wait([
        service.markBackupConfirmed(backupA!.phrase),
        identityService.importIdentity(seedB),
      ]);
      expect(
        await service.hasBackup(),
        isFalse,
        reason: 'a phrase that recovers the OLD key must not mark the '
            'NEW identity as backed up',
      );

      // Order B: the import is already in flight when the confirmation
      // is issued — same invariant.
      final keyPairA2 = await Ed25519().newKeyPair();
      final seedA2 =
          Uint8List.fromList(await keyPairA2.extractPrivateKeyBytes());
      final backupB = await service.backupCurrentIdentity();
      expect(backupB, isNotNull);
      final importFuture = identityService.importIdentity(seedA2);
      await service.markBackupConfirmed(backupB!.phrase);
      await importFuture;
      expect(await service.hasBackup(), isFalse);
    });

    test(
        'markBackupConfirmed still records a marker for the CURRENT '
        'identity', () async {
      final storage = _InMemorySecureStorage();
      final identityService = IdentityService(storage);
      final service = MnemonicService(identityService, storage: storage);

      await identityService.generateIdentity();
      final backup = await service.backupCurrentIdentity();
      await service.markBackupConfirmed(backup!.phrase);

      expect(await service.hasBackup(), isTrue);
      expect(storage.data[SecureStorageKeys.mnemonicBackup], isNotNull);
    });

    test('recover B while A cached -> all read paths return B', () async {
      // End-to-end through the REAL providers: identityStateProvider and
      // activeIdentitiesProvider must both serve the recovered key —
      // enforced by identityRevisionProvider, not by call-site
      // invalidation.
      final storage = _InMemorySecureStorage();
      final container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      final identityService = container.read(identityServiceProvider);
      final service = container.read(mnemonicServiceProvider);

      final identityA = await identityService.generateIdentity();
      expect(
        (await container.read(identityStateProvider.future))!.publicKey,
        equals(identityA.publicKey),
      );
      final idsA = await container.read(activeIdentitiesProvider.future);
      expect(idsA.single.did, 'did:alex:${identityA.shortId}');

      // Build identity B's phrase in a separate store.
      final storageB = _InMemorySecureStorage();
      final identityServiceB = IdentityService(storageB);
      final serviceB = MnemonicService(identityServiceB, storage: storageB);
      await identityServiceB.generateIdentity();
      final backupB = await serviceB.backupCurrentIdentity();
      expect(backupB, isNotNull);

      final recovered = await service.recoverFromMnemonic(backupB!.words);
      expect(recovered, isNotNull);
      expect(recovered!.publicKey, isNot(equals(identityA.publicKey)));

      // The revision bump inside importIdentity invalidated both
      // providers synchronously — no explicit invalidate needed here.
      final state = await container.read(identityStateProvider.future);
      expect(state!.publicKey, equals(recovered.publicKey));
      final idsB = await container.read(activeIdentitiesProvider.future);
      expect(idsB.single.did, 'did:alex:${recovered.shortId}');
    });

    test('key rotation -> providers reflect the new key', () async {
      final storage = _InMemorySecureStorage();
      final container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(container.dispose);

      final identityService = container.read(identityServiceProvider);
      final overview = container.read(securityOverviewServiceProvider);

      final identityA = await identityService.generateIdentity();
      final idsA = await container.read(activeIdentitiesProvider.future);
      expect(idsA.single.did, 'did:alex:${identityA.shortId}');

      // Rotation goes through IdentityService (single owner); the
      // revision bump makes every dependent provider rebuild.
      final rotated = await overview.generateNewKeypair(KeyType.ed25519);
      expect(rotated.did, isNot('did:alex:${identityA.shortId}'));

      final idsB = await container.read(activeIdentitiesProvider.future);
      expect(idsB.single.did, rotated.did);
      final state = await container.read(identityStateProvider.future);
      expect(state!.publicKey, isNot(equals(identityA.publicKey)));

      // The previously confirmed backup marker was cleared by the
      // rotation path.
      final mnemonic = container.read(mnemonicServiceProvider);
      await mnemonic.markBackupConfirmed('old phrase');
      expect(await mnemonic.hasBackup(), isTrue);
      await overview.generateNewKeypair(KeyType.ed25519);
      expect(await mnemonic.hasBackup(), isFalse);
    });

    test('mnemonicServiceProvider reads correctly', () {
      final container = ProviderContainer(overrides: [
        identityServiceProvider.overrideWithValue(fakeIdentity),
        secureStorageServiceProvider
            .overrideWithValue(_InMemorySecureStorage()),
      ]);
      addTearDown(container.dispose);

      final service = container.read(mnemonicServiceProvider);
      expect(service, isA<MnemonicService>());
    });
  });
}
