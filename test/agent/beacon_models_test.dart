import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/beacon_models.dart';

void main() {
  group('Beacon v2 Cryptographic Envelope Tests (ALX-006 §3)', () {
    late SimpleKeyPair keyPair;
    late SimplePublicKey pubKey;

    setUp(() async {
      final algorithm = Ed25519();
      keyPair = await algorithm.newKeyPair();
      pubKey = await keyPair.extractPublicKey();
    });

    test('derives agent_id correctly from Ed25519 public key', () {
      final agentId = BeaconEnvelope.deriveAgentId(pubKey.bytes);
      expect(agentId.startsWith('bcn_'), isTrue);
      expect(agentId.length, 16); // 'bcn_' (4) + 12 hex chars = 16
    });

    test('serializes maps canonically with sorted keys', () {
      final map1 = {
        'z': 1,
        'a': 2,
        'm': {'y': 'val2', 'b': 'val1'}
      };
      final canonicalStr = toCanonicalJson(map1);

      // Verify 'a' precedes 'm', 'm' precedes 'z', and nested 'b' precedes 'y'
      expect(canonicalStr, '{"a":2,"m":{"b":"val1","y":"val2"},"z":1}');
    });

    test('creates and cryptographically verifies a valid Beacon v2 envelope',
        () async {
      final payload = {
        'cid': 'bafk_ancient_manuscript_01',
        'offered_credits': 30.0,
        'urgency': 'critical',
      };

      final envelope = await BeaconEnvelope.create(
        kind: 'preservation_bounty',
        keyPair: keyPair,
        payload: payload,
      );

      expect(envelope.v, 2);
      expect(envelope.kind, 'preservation_bounty');
      expect(envelope.agentId, BeaconEnvelope.deriveAgentId(pubKey.bytes));
      expect(envelope.pubkey, bytesToHex(pubKey.bytes));
      expect(envelope.sig.length, 128); // 64 bytes in hex = 128 chars

      final isValid = await envelope.verify();
      expect(isValid, isTrue);
    });

    test('rejects tampered payload during verification', () async {
      final envelope = await BeaconEnvelope.create(
        kind: 'archive_receipt',
        keyPair: keyPair,
        payload: {'credits': 10.0},
      );

      // Tamper with payload
      final tampered = BeaconEnvelope(
        v: envelope.v,
        kind: envelope.kind,
        agentId: envelope.agentId,
        ts: envelope.ts,
        nonce: envelope.nonce,
        pubkey: envelope.pubkey,
        sig: envelope.sig,
        payload: {'credits': 1000.0}, // Tampered!
      );

      final isValid = await tampered.verify();
      expect(isValid, isFalse);
    });

    test('rejects spoofed agent_id that does not match public key', () async {
      final envelope = await BeaconEnvelope.create(
        kind: 'archive_receipt',
        keyPair: keyPair,
        payload: {'status': 'verified'},
      );

      final spoofed = BeaconEnvelope(
        v: envelope.v,
        kind: envelope.kind,
        agentId: 'bcn_spoofed_id', // Does not match pubkey
        ts: envelope.ts,
        nonce: envelope.nonce,
        pubkey: envelope.pubkey,
        sig: envelope.sig,
        payload: envelope.payload,
      );

      final isValid = await spoofed.verify();
      expect(isValid, isFalse);
    });

    test('encodes and parses [BEACON v2] framed text', () async {
      final envelope = await BeaconEnvelope.create(
        kind: 'por_challenge',
        keyPair: keyPair,
        payload: {'challenge_nonce': 'test_nonce_1234'},
      );

      final framedText = envelope.toFramedText();
      expect(framedText.startsWith('[BEACON v2]\n{'), isTrue);

      final parsed = BeaconEnvelope.parse(framedText);
      expect(parsed, isNotNull);
      expect(parsed!.agentId, envelope.agentId);
      expect(parsed.kind, 'por_challenge');
      expect(parsed.payload['challenge_nonce'], 'test_nonce_1234');

      final isParsedValid = await parsed.verify();
      expect(isParsedValid, isTrue);
    });
  });
}
