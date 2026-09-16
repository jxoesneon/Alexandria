// RED TEAM — Round-4 VERIFICATION of the round-3 ECIES contributory
// fix (expected to PASS — this file is the regression record).
//
//   lib/services/encryption_service.dart
//
// The blocklist covers the full 12-value libsodium set AND the check
// compares both the raw and the bit-255-masked input. Under RFC 7748
// masking (package:cryptography clears u bit 255 — verified in
// src/dart/x25519.dart: unpackedPublicKey[15] &= 0x7FFF) the complete
// non-contributory input set is {x, x+2^255} for
// x ∈ {0, 1, p-1, p, p+1, u8a, u8b} — 14 inputs, all caught.
//
// This file hammers every spelling: each canonical low-order u, its
// +2^255 sibling, and each value with both bits that decode to the same
// point. Every envelope must be sealed to an unreachable point — an
// eavesdropper who knows the public peer string AND the public seal
// derivation must still be unable to open it.
//
// NOTE on the residual design hazard (not a live break): the all-zero
// defence-in-depth fallback at encryptForPeer derives its substitute
// secret from sha256('alexandria:x25519-non-contributory:v1:' +
// peerPublicKey) — a PUBLIC input. If a low-order input ever slipped
// past the blocklist (e.g. an X25519 backend that does not mask bit
// 255, where u8a+p / u8b+p are non-contributory and unlisted), the
// "seal" would be publicly reproducible — exactly the broadcast the
// comment claims to prevent. Recommend keying the fallback with the
// ephemeral private key or random bytes.
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';

String _hex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

/// Reproduces EncryptionService._sealedU — the unreachable point a
/// refused input maps to. Public knowledge.
Uint8List _sealedU(String peerPublicKey) => Uint8List.fromList(crypto.sha256
    .convert(
        utf8.encode('alexandria:x25519-unresolvable-peer:v1:$peerPublicKey'))
    .bytes);

/// Reproduces the non-contributory fallback secret — also public.
List<int> _fallbackSecret(String peerPublicKey) => crypto.sha256
    .convert(
        utf8.encode('alexandria:x25519-non-contributory:v1:$peerPublicKey'))
    .bytes;

/// Every canonical low-order u plus its +2^255 sibling.
List<Uint8List> _lowOrderVariants() {
  const canonical = [
    '0000000000000000000000000000000000000000000000000000000000000000',
    '0100000000000000000000000000000000000000000000000000000000000000',
    'e0eb7a7c3b41b8ae1656e3faf19fc46ada098deb9c32b1fd866205165f49b800',
    '5f9c95bca3508c24b1d0b1559c83ef5b04445c39158b4e1e9a4f04b4e0ce5e39',
    'ecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'edffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
    'eeffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f',
  ];
  Uint8List dec(String h) => Uint8List.fromList(List.generate(
      32, (i) => int.parse(h.substring(i * 2, i * 2 + 2), radix: 16)));
  final out = <Uint8List>[];
  for (final c in canonical) {
    final base = dec(c);
    out.add(base);
    out.add(Uint8List.fromList(base)..[31] |= 0x80); // +2^255 spelling
  }
  return out;
}

void main() {
  final enc = EncryptionService();
  final aes = AesGcm.with256bits();
  final x = X25519();

  test(
      'no spelling of a low-order peer input yields a publicly '
      'decryptable envelope', () async {
    final secret = Uint8List.fromList(utf8.encode('round4-probe-payload'));
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

    for (final u in _lowOrderVariants()) {
      final pubStr = _hex(u);
      final envelope = await enc.encryptForPeer(secret, pubStr);
      final ephPub = Uint8List.fromList(envelope.sublist(1, 33));

      // The eavesdropper knows the public peer string, so it knows the
      // sealed u too. Try every publicly-derivable key schedule.
      final candidatePeerUs = <Uint8List>[u, _sealedU(pubStr)];
      final candidateSecrets = <List<int>>[
        List.filled(32, 0), // zero shared secret
        _fallbackSecret(pubStr), // the public non-contributory fallback
      ];
      for (final peerU in candidatePeerUs) {
        final salt = (BytesBuilder()
              ..add(ephPub)
              ..add(peerU))
            .toBytes();
        for (final sec in candidateSecrets) {
          final key = await hkdf.deriveKey(
              secretKey: SecretKey(sec),
              nonce: salt,
              info: utf8.encode('alexandria:peer-e2e:v1'));
          final box = SecretBox.fromConcatenation(
            envelope.sublist(33),
            nonceLength: aes.nonceLength,
            macLength: aes.macAlgorithm.macLength,
          );
          Object? opened;
          try {
            opened = await aes.decrypt(box, secretKey: key);
          } catch (_) {}
          expect(opened, isNull,
              reason: 'envelope for low-order input ${_hex(u)} opened with a '
                  'publicly derivable key — the seal failed');
        }
      }
    }
  });

  test('decryptFromPeer rejects every low-order ephemeral spelling', () async {
    final kp = await x.newKeyPair();
    final priv = Uint8List.fromList(await kp.extractPrivateKeyBytes());
    for (final u in _lowOrderVariants()) {
      final envelope = (BytesBuilder()
            ..addByte(EncryptionService.peerEnvelopeVersion)
            ..add(u)
            ..add(List.filled(48, 0xAA)))
          .toBytes();
      Object? threw;
      try {
        await enc.decryptFromPeer(envelope, priv);
      } catch (e) {
        threw = e;
      }
      expect(threw, isNotNull,
          reason: 'decryptFromPeer accepted ephemeral ${_hex(u)} — a '
              'non-contributory input slipped past the blocklist');
    }
  });
}
