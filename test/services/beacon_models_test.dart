import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';

void main() {
  group('BeaconModels Tests', () {
    test('bytesToHex and hexToBytes round trip', () {
      final bytes = [0, 1, 15, 16, 255, 128, 42];
      final hex = bytesToHex(bytes);
      expect(hex, '00010f10ff802a');
      expect(hexToBytes(hex), bytes);
      expect(hexToBytes('00 01 0f 10 ff 80 2a'), bytes);
    });

    test('deriveAgentId generates canonical identifier', () {
      final bytes = List<int>.filled(32, 0xAB);
      final agentId = BeaconEnvelope.deriveAgentId(bytes);
      expect(agentId, 'bcn_abababababab');
    });

    test('BeaconEnvelope creates, signs, verifies, and frames correctly',
        () async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPair();

      final envelope = await BeaconEnvelope.create(
        kind: 'bounty_broadcast',
        keyPair: keyPair,
        payload: {
          'action': 'preserve',
          'cid': 'bafy_test_123',
          'credits': 15.0,
        },
        clientInfo: {
          'client': 'Alexandria Test',
          'version': '1.0.0',
        },
      );

      expect(envelope.v, 2);
      expect(envelope.kind, 'bounty_broadcast');
      expect(envelope.clientInfo?['client'], 'Alexandria Test');

      final isValid = await envelope.verify();
      expect(isValid, isTrue);

      final framed = envelope.toFramedText();
      expect(framed.startsWith('[BEACON v2]'), isTrue);

      final parsed = BeaconEnvelope.parse(framed);
      expect(parsed, isNotNull);
      expect(parsed!.agentId, envelope.agentId);
      expect(parsed.sig, envelope.sig);
      expect(await parsed.verify(), isTrue);

      // Verify corrupt signature fails
      final corrupt = BeaconEnvelope(
        v: parsed.v,
        kind: parsed.kind,
        agentId: parsed.agentId,
        ts: parsed.ts,
        nonce: parsed.nonce,
        pubkey: parsed.pubkey,
        sig: '00' * 64,
        payload: parsed.payload,
      );
      expect(await corrupt.verify(), isFalse);
    });

    test('MoltbookPost serialization and deserialization', () {
      final now = DateTime.now();
      final post = MoltbookPost(
        id: 42,
        submolt: 'alexandria-bounties',
        title: 'Preserve Gutenberg Texts',
        content: 'Bounty posted for high priority archiving.',
        authorAgentId: 'bcn_1234567890ab',
        upvotes: 7,
        timestamp: now,
      );

      expect(post.isBeaconVerified, isFalse);
      final json = post.toJson();
      expect(json['id'], 42);
      expect(json['upvotes'], 7);

      final fromJson = MoltbookPost.fromJson(json);
      expect(fromJson.id, post.id);
      expect(fromJson.title, post.title);
      expect(fromJson.authorAgentId, post.authorAgentId);
    });

    test('PreservationBounty serialization and deserialization', () {
      final now = DateTime.now();
      final bounty = PreservationBounty(
        id: 'bty_99',
        cid: 'bafy_sample',
        doi: '10.1000/182',
        title: 'Archival Seed',
        targetShards: 8,
        offeredCredits: 50.0,
        urgency: 'critical',
        originAgentId: 'bcn_agent',
        createdAt: now,
        funded: true,
      );

      final json = bounty.toJson();
      expect(json['id'], 'bty_99');
      expect(json['funded'], isTrue);
      expect(json['doi'], '10.1000/182');

      final fromJson = PreservationBounty.fromJson(json);
      expect(fromJson.id, bounty.id);
      expect(fromJson.cid, bounty.cid);
      expect(fromJson.targetShards, 8);
      expect(fromJson.offeredCredits, 50.0);
      expect(fromJson.funded, isTrue);
    });
  });
}
