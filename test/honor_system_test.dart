import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/logic/honor_system.dart';

void main() {
  group('HonorSystem Reputation Tests', () {
    late HonorSystem honorSystem;

    setUp(() {
      honorSystem = HonorSystem();
    });

    test('records valid votes and calculates weighted trust score', () {
      honorSystem.recordVote(
        validatorId: 'val_alice',
        targetCid: 'cid_100',
        score: 1,
        reputation: 90, // log10(100) = 2.0
      );

      honorSystem.recordVote(
        validatorId: 'val_bob',
        targetCid: 'cid_100',
        score: 1,
        reputation: 990, // log10(1000) = 3.0
      );

      final score = honorSystem.computeTrustScore('cid_100');
      expect(score, equals(5)); // 2.0 + 3.0 = 5
    });

    test('disallows invalid score bounds', () {
      expect(
          () => honorSystem.recordVote(
              validatorId: 'val', targetCid: 'cid', score: 2),
          throwsArgumentError);
      expect(
          () => honorSystem.recordVote(
              validatorId: 'val', targetCid: 'cid', score: 0),
          throwsArgumentError);
    });

    test(
        'one ballot per validator per target — repeat votes replace, '
        'never stack', () {
      // Without dedup a validator could call recordVote N times and
      // multiply its weight N-fold; a re-vote must REPLACE the prior
      // ballot for the same (validatorId, targetCid).
      honorSystem.recordVote(
        validatorId: 'val_alice',
        targetCid: 'cid_300',
        score: 1,
        reputation: 90, // weight 2.0
      );
      honorSystem.recordVote(
        validatorId: 'val_alice',
        targetCid: 'cid_300',
        score: 1,
        reputation: 90,
      );
      honorSystem.recordVote(
        validatorId: 'val_alice',
        targetCid: 'cid_300',
        score: 1,
        reputation: 90,
      );
      expect(honorSystem.computeTrustScore('cid_300'), equals(2));

      // A validator may change its mind - newest ballot stands.
      honorSystem.recordVote(
        validatorId: 'val_alice',
        targetCid: 'cid_300',
        score: -1,
        reputation: 90,
      );
      expect(honorSystem.computeTrustScore('cid_300'), equals(-2));

      // ...while votes on OTHER targets are unaffected.
      honorSystem.recordVote(
        validatorId: 'val_alice',
        targetCid: 'cid_301',
        score: 1,
        reputation: 90,
      );
      expect(honorSystem.computeTrustScore('cid_301'), equals(2));
      expect(honorSystem.computeTrustScore('cid_300'), equals(-2));
    });

    test('validateContent and getTrustScore aliases work correctly', () {
      honorSystem.validateContent(
        validatorId: 'val_charlie',
        targetCid: 'cid_200',
        score: -1,
        reputation: 90,
      );

      expect(honorSystem.getTrustScore('cid_200'), equals(-2));
    });

    test('honorSystemProvider provides HonorSystem instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(honorSystemProvider), isA<HonorSystem>());
    });

    test('recordVote invokes the persistence hook', () async {
      ValidationVote? captured;
      honorSystem.onVoteRecorded = (vote) async => captured = vote;

      honorSystem.recordVote(
        validatorId: 'val_alice',
        targetCid: 'cid_900',
        score: -1,
        reputation: 90,
      );
      await Future<void>.delayed(Duration.zero);

      expect(captured?.targetCid, 'cid_900');
      expect(captured?.score, -1);
      expect(captured?.reputation, 90);
    });

    test('restoreVote replays a persisted ballot without re-writing', () {
      var writes = 0;
      honorSystem.onVoteRecorded = (_) async => writes++;

      honorSystem.restoreVote(
        validatorId: 'val_alice',
        targetCid: 'cid_910',
        score: 1,
        reputation: 90,
      );

      expect(honorSystem.computeTrustScore('cid_910'), equals(2));
      expect(writes, 0);
    });

    test('restoreVote dedups per validator — newest ballot wins', () {
      honorSystem.restoreVote(
        validatorId: 'val_alice',
        targetCid: 'cid_920',
        score: 1,
        reputation: 90,
      );
      honorSystem.restoreVote(
        validatorId: 'val_alice',
        targetCid: 'cid_920',
        score: -1,
        reputation: 90,
      );

      expect(honorSystem.computeTrustScore('cid_920'), equals(-2));
    });
  });
}
