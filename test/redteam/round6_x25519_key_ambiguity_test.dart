// RED TEAM PoC — Round-6: _resolvePeerAgreementKey's "explicit" key-type
// disambiguation is probabilistically wrong for HALF of all real X25519
// public keys.
//
//   lib/services/encryption_service.dart:241-260
//     if (_isCanonicalEd25519Key(raw)) {
//       mapped = ed25519PublicToX25519(raw);   // ← interprets u as Ed y
//       ...
//       return mapped;                        // ← WRONG point
//     }
//     return raw;                             // raw-u path
//
// The comment admits the ambiguity ("~50% of Montgomery u-coordinates
// also parse as a valid Edwards encoding") and claims the canonical
// path "is validated to round-trip" — but it is only validated for ONE
// fixture. For every identity whose Montgomery u happens to satisfy
// `_isCanonicalEd25519Key` (little-endian y < p with x² a quadratic
// residue — ~1/2 of all keys), `encryptForPeer(hex(u))` re-maps u to a
// DIFFERENT curve point u' = (1+y)/(1−y). The envelope then agrees
// with u' — a point whose private key nobody holds — and the intended
// recipient's `decryptFromPeer(env, xPriv)` fails AEAD. Confidentiality
// survives (the ciphertext is sealed to a dead key) but availability
// and the documented contract are broken for ~50% of advertised keys —
// silently, per-key, with no way for the sender to detect it.
//
// Asserts the SECURE expectation: every real X25519 public key a peer
// can advertise via x25519PublicKeyBytes must round-trip.
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';

String _hex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final enc = EncryptionService();

  test('every advertised X25519 u-coordinate round-trips through '
      'encryptForPeer/decryptFromPeer', () async {
    final ed = Ed25519();
    final x = X25519();
    final data = Uint8List.fromList('peer-addressed-payload'.codeUnits);

    final ambiguous = <int>[];
    for (var i = 1; i <= 32; i++) {
      // Deterministic Ed25519 identity seeds — the same derivation
      // IdentityService performs for x25519PrivateKeyBytes /
      // x25519PublicKeyBytes.
      final seed = Uint8List(32)..[0] = i;
      final kp = await ed.newKeyPairFromSeed(seed);
      final edPub =
          Uint8List.fromList((await kp.extractPublicKey()).bytes);
      final xPriv = EncryptionService.ed25519SeedToX25519Seed(seed);
      // This u-coordinate IS IdentityService.x25519PublicKeyBytes()
      // output: the birational image of the Ed25519 identity key.
      final xPub = EncryptionService.ed25519PublicToX25519(edPub);

      // Invariant sanity: xPub is genuinely the X25519 public key for
      // xPriv (libsodium pk_to_curve25519/sk_to_curve25519 agreement).
      final xKp = await x.newKeyPairFromSeed(xPriv);
      expect(
        Uint8List.fromList((await xKp.extractPublicKey()).bytes),
        equals(xPub),
      );

      // The documented sender path: encrypt to the advertised raw
      // u-coordinate.
      final env = await enc.encryptForPeer(data, _hex(xPub));
      try {
        final plain = await enc.decryptFromPeer(env, xPriv);
        expect(plain, equals(data));
      } catch (_) {
        ambiguous.add(i);
      }
    }

    expect(ambiguous, isEmpty,
        reason:
            'seeds $ambiguous produced X25519 u-coordinates that satisfy '
            '_isCanonicalEd25519Key, so _resolvePeerAgreementKey '
            're-mapped them as Ed25519 keys and sealed the envelope to '
            'the wrong curve point — undecryptable by the advertised '
            'private key. ~50% of real peer keys are affected; the '
            '"validated to round-trip" claim held only for the single '
            'round-3 fixture.');
  });
}
