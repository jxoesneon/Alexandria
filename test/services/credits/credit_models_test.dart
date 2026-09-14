import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/credits/credit_models.dart';

void main() {
  group('CreditModels Tests', () {
    test('CreditTransaction computes hash, serializes and deserializes', () {
      final now = DateTime.now();
      final hash = CreditTransaction.computeHash(
        id: 'tx_123',
        timestamp: now,
        type: CreditType.storageReward,
        amount: 25.5,
        description: 'Storage seeding reward',
        referenceId: 'ref_abc',
        isAttested: true,
      );

      final tx = CreditTransaction(
        id: 'tx_123',
        timestamp: now,
        type: CreditType.storageReward,
        amount: 25.5,
        description: 'Storage seeding reward',
        referenceId: 'ref_abc',
        hash: hash,
        isAttested: true,
      );

      final json = tx.toJson();
      expect(json['id'], 'tx_123');
      expect(json['amount'], 25.5);
      expect(json['isAttested'], isTrue);

      final fromJson = CreditTransaction.fromJson(json);
      expect(fromJson.id, tx.id);
      expect(fromJson.type, CreditType.storageReward);
      expect(fromJson.amount, 25.5);
      expect(fromJson.hash, hash);
      expect(fromJson.isAttested, isTrue);

      // Deserialization with DateTime directly
      final fromDriftMap = CreditTransaction.fromJson({
        'id': 'tx_drift',
        'timestamp': now,
        'type': 'unknown_type',
        'amount': 10,
        'description': 'test',
        'hash': 'h',
      });
      expect(fromDriftMap.type, CreditType.storageReward);
      expect(fromDriftMap.isAttested, isFalse);
    });

    test('PoCHMetrics calculates compliance and bandwidth multipliers', () {
      final compliant = PoCHMetrics(
        allocatedStorageBytes: 1500 * 1024 * 1024,
        dailySeedingBytes: 600 * 1024 * 1024,
        dailyPoRChallengesAnswered: 15,
        lastCalculated: DateTime(2026, 1, 1),
      );

      expect(compliant.score, greaterThanOrEqualTo(0.5));
      expect(compliant.isCompliant, isTrue);
      expect(compliant.bandwidthMultiplier, greaterThanOrEqualTo(1.0));

      final nonCompliant = PoCHMetrics(
        allocatedStorageBytes: 100 * 1024 * 1024,
        dailySeedingBytes: 10 * 1024 * 1024,
        dailyPoRChallengesAnswered: 1,
        lastCalculated: DateTime(2026, 1, 1),
      );

      expect(nonCompliant.score, lessThan(0.5));
      expect(nonCompliant.isCompliant, isFalse);
      expect(nonCompliant.bandwidthMultiplier, lessThan(0.15));

      final json = compliant.toJson();
      expect(json['isCompliant'], isTrue);
      expect(json['allocatedStorageBytes'], 1500 * 1024 * 1024);
    });

    test('SponsorshipSlot contextual matching and serialization', () {
      const slot = SponsorshipSlot(
        campaignId: 'camp_001',
        sponsorName: 'Open Archive Foundation',
        badgeText: 'Preserving History',
        actionUrl: 'https://openarchive.org',
        categories: ['book', 'history'],
        tags: ['archaeology', 'classics'],
        rewardCredits: 5.0,
      );

      expect(slot.matchesContext('book', []), isTrue);
      expect(slot.matchesContext('science', ['archaeology']), isTrue);
      expect(slot.matchesContext('music', ['jazz']), isFalse);

      final json = slot.toJson();
      expect(json['sponsorName'], 'Open Archive Foundation');
      expect(json['rewardCredits'], 5.0);
    });

    test('ImpressionReceipt serializes to JSON', () {
      final receipt = ImpressionReceipt(
        campaignId: 'camp_001',
        timestamp: DateTime(2026, 1, 1),
        dwellTimeSeconds: 45.0,
        nonce: 'nonce_xyz',
        grossCredits: 1.0,
        clientKickback: 0.6,
        archivalCommonsPool: 0.3,
        protocolFee: 0.1,
      );

      final json = receipt.toJson();
      expect(json['campaignId'], 'camp_001');
      expect(json['dwellTimeSeconds'], 45.0);
      expect(json['clientKickback'], 0.6);
    });
  });
}
