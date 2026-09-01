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
  });
}
