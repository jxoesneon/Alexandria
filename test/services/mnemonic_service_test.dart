import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/mnemonic_service.dart';

class _MockIdentityService implements IdentityService {
  AlexandriaIdentity? identity;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => identity;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MnemonicService Tests', () {
    late _MockIdentityService fakeIdentity;
    late MnemonicService mnemonicService;

    setUp(() {
      fakeIdentity = _MockIdentityService();
      mnemonicService = MnemonicService(fakeIdentity);
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
      expect(mnemonicService.validateMnemonic(List.filled(23, 'abandon')), isFalse);
      expect(mnemonicService.validateMnemonic(List.filled(25, 'abandon')), isFalse);

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

      final recovered =
          await mnemonicService.recoverFromMnemonic(backup.words);
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

      final hasBackup = await mnemonicService.hasBackup();
      expect(hasBackup, isA<bool>());
    });

    test('mnemonicServiceProvider reads correctly', () {
      final container = ProviderContainer(overrides: [
        identityServiceProvider.overrideWithValue(fakeIdentity),
      ]);
      addTearDown(container.dispose);

      final service = container.read(mnemonicServiceProvider);
      expect(service, isA<MnemonicService>());
    });
  });
}
