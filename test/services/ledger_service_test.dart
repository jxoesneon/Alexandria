import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ledger_service.dart';

class _FakeIdentityService implements IdentityService {
  _FakeIdentityService(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: publicKeyBytes,
        privateKey: Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  Future<Uint8List> sign(Uint8List data) async {
    final sig = await Ed25519().sign(data, keyPair: keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LedgerService Tests', () {
    late _FakeIdentityService identity;
    late LedgerService ledger;

    setUp(() async {
      final algo = Ed25519();
      final kp = await algo.newKeyPair();
      final pub = await kp.extractPublicKey();
      identity = _FakeIdentityService(kp, Uint8List.fromList(pub.bytes));
      ledger = LedgerService(identity);
    });

    test('ledgerServiceProvider exposes a LedgerService instance', () {
      final container = ProviderContainer(overrides: [
        identityServiceProvider.overrideWithValue(identity),
      ]);
      addTearDown(container.dispose);

      final service = container.read(ledgerServiceProvider);
      expect(service, isA<LedgerService>());
    });

    test('records actions and maintains Merkle chain integrity', () async {
      expect(ledger.entries, isEmpty);
      expect(ledger.verifyChain(), isTrue);

      final e1 = await ledger.recordAction(
        action: LedgerActionType.pinContent,
        contentCid: 'bafy_pin_1',
      );
      expect(e1.index, equals(0));
      expect(e1.contentCid, equals('bafy_pin_1'));
      expect(e1.previousHash, equals(LedgerService.genesisHash));
      expect(e1.signature, isNotEmpty);
      expect(ledger.verifyChain(), isTrue);

      final e2 = await ledger.recordAction(
        action: LedgerActionType.validateHash,
        contentCid: 'bafy_val_2',
      );
      expect(e2.index, equals(1));
      expect(e2.previousHash, equals(e1.computeHash()));
      expect(ledger.verifyChain(), isTrue);

      final e3 = await ledger.recordAction(
        action: LedgerActionType.curateCollection,
        contentCid: 'bafy_cur_3',
      );
      expect(e3.index, equals(2));
      expect(e3.previousHash, equals(e2.computeHash()));
      expect(ledger.verifyChain(), isTrue);
      expect(ledger.entries.length, equals(3));
    });

    test('calculates total and effective reputation scores', () async {
      expect(ledger.totalReputation, equals(0.0));

      await ledger.recordAction(
        action: LedgerActionType.pinContent, // 1.0
        contentCid: 'bafy_1',
      );
      await ledger.recordAction(
        action: LedgerActionType.validateHash, // 2.0
        contentCid: 'bafy_2',
      );

      expect(ledger.totalReputation, equals(3.0));

      // Effective reputation with decay
      final now = DateTime.now();
      final effectiveNow = ledger.getEffectiveReputation(now);
      expect(effectiveNow, closeTo(3.0, 0.001));

      final tenDaysAgo = now.subtract(const Duration(days: 10));
      final effectiveDecayed = ledger.getEffectiveReputation(tenDaysAgo);
      expect(effectiveDecayed, lessThan(3.0));
      expect(effectiveDecayed, greaterThan(0.0));
    });

    test('exports and imports ledger JSON preserving chain integrity', () async {
      await ledger.recordAction(
        action: LedgerActionType.createContent,
        contentCid: 'bafy_exported_1',
      );
      await ledger.recordAction(
        action: LedgerActionType.endorseContent,
        contentCid: 'bafy_exported_2',
      );

      final jsonString = ledger.exportToJson();
      expect(jsonString, isNotEmpty);

      final newLedger = LedgerService(identity);
      final importSuccess = await newLedger.importFromJson(jsonString);
      expect(importSuccess, isTrue);
      expect(newLedger.entries.length, equals(2));
      expect(newLedger.verifyChain(), isTrue);
      expect(newLedger.totalReputation, equals(ledger.totalReputation));

      final corruptSuccess = await newLedger.importFromJson('invalid json string');
      expect(corruptSuccess, isFalse);
    });

    test('adds cross-signatures to ledger entries', () async {
      final entry = await ledger.recordAction(
        action: LedgerActionType.crossSignLedger,
        contentCid: 'bafy_cross',
      );

      final peerKey = Uint8List.fromList(List.filled(32, 7));
      final peerSig = Uint8List.fromList(List.filled(64, 8));

      await ledger.addCrossSignature(
        entryIndex: entry.index,
        signerPublicKey: peerKey,
        signature: peerSig,
      );

      expect(ledger.entries[entry.index].crossSignatures.length, equals(1));
      final cross = ledger.entries[entry.index].crossSignatures.first;
      expect(cross.signerPublicKey, equals(peerKey));
      expect(cross.signature, equals(peerSig));

      // Out of bounds entry index does nothing
      await ledger.addCrossSignature(
        entryIndex: 99,
        signerPublicKey: peerKey,
        signature: peerSig,
      );
      expect(ledger.entries[entry.index].crossSignatures.length, equals(1));
    });

    test('daily limits and action counting', () async {
      expect(ledger.isWithinDailyLimit(LedgerActionType.pinContent), isTrue);

      await ledger.recordAction(
        action: LedgerActionType.pinContent,
        contentCid: 'bafy_daily_pin',
      );

      final counts = ledger.getTodayActionCounts();
      expect(counts[LedgerActionType.pinContent], equals(1));
      expect(ledger.isWithinDailyLimit(LedgerActionType.pinContent), isTrue);
    });

    test('ReputationWeights and LedgerEntry serialization', () {
      for (final action in LedgerActionType.values) {
        expect(ReputationWeights.getWeight(action), greaterThan(0));
      }

      final entry = LedgerEntry(
        index: 0,
        timestamp: DateTime.now(),
        action: LedgerActionType.proposeMetadataFix,
        contentCid: 'bafy_test',
        previousHash: LedgerService.genesisHash,
        signature: Uint8List.fromList([1, 2, 3]),
      );

      expect(entry.getReputationPoints(accepted: false), equals(0.5));
      expect(entry.getReputationPoints(accepted: true), equals(1.0));

      final json = entry.toJson();
      final roundTrip = LedgerEntry.fromJson(json);
      expect(roundTrip.index, equals(entry.index));
      expect(roundTrip.contentCid, equals(entry.contentCid));
      expect(roundTrip.action, equals(entry.action));
    });
  });
}
