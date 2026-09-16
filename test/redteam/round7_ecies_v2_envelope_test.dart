// RED TEAM verification - Round-7: ECIES v2 multi-box envelope abuse.
//
//   lib/services/encryption_service.dart:184-275
//     v2 layout: version(1) ‖ ephemeralX25519Pub(32) ‖ boxCount(1)
//                ‖ box×count   (box = nonce ‖ ciphertext ‖ tag)
//
// Probes: boxCount bounds (OOM/alloc), per-box AEAD independence,
// downgrade (box stripping / version rewrite), and the tagged
// ed25519:/x25519: contract on both encrypt and decrypt.
// All asserts are the SECURE expectation - expected to PASS.
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/encryption_service.dart';

String _hex(Uint8List b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final enc = EncryptionService();
  final data = Uint8List.fromList('multi-box-payload'.codeUnits);

  Future<({Uint8List xPriv, Uint8List xPub, Uint8List edPub})> makePeer(
      int seedByte) async {
    final ed = Ed25519();
    final seed = Uint8List(32)..[0] = seedByte;
    final kp = await ed.newKeyPairFromSeed(seed);
    final edPub = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    return (
      xPriv: EncryptionService.ed25519SeedToX25519Seed(seed),
      xPub: EncryptionService.ed25519PublicToX25519(edPub),
      edPub: edPub,
    );
  }

  test(
      'boxCount bounds: 0, 1, non-dividing and oversized counts are '
      'rejected without unbounded allocation', () async {
    final peer = await makePeer(7);
    // A well-formed v1 envelope to borrow the ephemeral key from.
    final env = await enc.encryptForPeer(data, 'x25519:${_hex(peer.xPub)}');
    final eph = env.sublist(1, 33);

    Uint8List v2(int count, List<int> payload) =>
        Uint8List.fromList([2, ...eph, count, ...payload]);

    // count=0 / count=1: v2 requires >= 2 boxes.
    expect(() => enc.decryptFromPeer(v2(0, List.filled(64, 1)), peer.xPriv),
        throwsA(isA<FormatException>()));
    expect(() => enc.decryptFromPeer(v2(1, List.filled(64, 1)), peer.xPriv),
        throwsA(isA<FormatException>()));
    // count=255 on a short payload: divisibility/min-box-length fails -
    // and the parse never allocates count×payload.
    expect(() => enc.decryptFromPeer(v2(255, List.filled(100, 1)), peer.xPriv),
        throwsA(isA<FormatException>()));
    // count divides payload but boxes are smaller than nonce+tag.
    expect(() => enc.decryptFromPeer(v2(4, List.filled(16, 1)), peer.xPriv),
        throwsA(isA<FormatException>()));
    // Truncated header.
    expect(
        () => enc.decryptFromPeer(Uint8List.fromList([2, ...eph]), peer.xPriv),
        throwsA(isA<FormatException>()));
  });

  test(
      'ambiguous untagged key produces a v2 envelope; each box is '
      'independently authenticated', () async {
    final peer = await makePeer(9);
    // The peer's Ed25519 identity pubkey, UNTAGGED - canonical Ed point
    // that is also a valid-looking u-coordinate → two candidates → v2.
    final env = await enc.encryptForPeer(data, _hex(peer.edPub));
    expect(env[0], 2, reason: 'ambiguous key must emit the multi-box form');
    final count = env[33];
    expect(count, greaterThanOrEqualTo(2));
    final payload = env.sublist(34);
    final boxLen = payload.length ~/ count;

    // Untampered decrypt - the box sealed to our real u opens.
    final plain = await enc.decryptFromPeer(env, peer.xPriv);
    expect(plain, data);

    // Tamper every box EXCEPT the one that authenticates for this
    // recipient → still opens (per-box AEAD independence).
    final tampered = Uint8List.fromList(env);
    for (var b = 1; b < count; b++) {
      tampered[34 + b * boxLen + boxLen - 1] ^= 0x01;
    }
    expect(await enc.decryptFromPeer(tampered, peer.xPriv), data);

    // Tamper the box bound to the recipient's real key → nothing
    // authenticates → hard failure, never wrong-plaintext.
    final tamperedAll = Uint8List.fromList(env);
    for (var b = 0; b < count; b++) {
      tamperedAll[34 + b * boxLen + boxLen - 1] ^= 0x01;
    }
    expect(
        () => enc.decryptFromPeer(tamperedAll, peer.xPriv), throwsA(anything));
  });

  test(
      'downgrade: stripping to the wrong box or rewriting the version '
      'cannot force a decrypt', () async {
    final peer = await makePeer(11);
    final env = await enc.encryptForPeer(data, _hex(peer.edPub));
    expect(env[0], 2);
    final count = env[33];
    final payload = env.sublist(34);
    final boxLen = payload.length ~/ count;

    // Strip everything but the LAST box (sealed to the raw-u reading -
    // NOT this ed-derived recipient's key) and rewrap as v1.
    final strippedToWrong = Uint8List.fromList(
        [1, ...env.sublist(1, 33), ...payload.sublist((count - 1) * boxLen)]);
    expect(() => enc.decryptFromPeer(strippedToWrong, peer.xPriv),
        throwsA(anything),
        reason: 'an attacker cannot make the recipient open a box sealed '
            'to a different agreement point');

    // Rewrap as v1 keeping ALL v2 payload bytes (including count byte)
    // → MAC fails → throw.
    final versionRewrite = Uint8List.fromList(env)..[0] = 1;
    expect(() => enc.decryptFromPeer(versionRewrite, peer.xPriv),
        throwsA(anything));

    // Unknown version byte → refused outright.
    final bogus = Uint8List.fromList(env)..[0] = 9;
    expect(() => enc.decryptFromPeer(bogus, peer.xPriv),
        throwsA(isA<FormatException>()));

    // v1 envelope with trailing garbage → AEAD fails, no silent accept.
    final v1 = await enc.encryptForPeer(data, 'x25519:${_hex(peer.xPub)}');
    final padded = Uint8List.fromList([...v1, 0xAA, 0xBB]);
    expect(() => enc.decryptFromPeer(padded, peer.xPriv), throwsA(anything));
  });

  test(
      'tagged keys are unambiguous: x25519: pins the raw u-coordinate, '
      'ed25519: pins the birational map', () async {
    final peer = await makePeer(13);

    // x25519:-tagged advertised key → single box v1, opens with xPriv.
    final envX = await enc.encryptForPeer(data, 'x25519:${_hex(peer.xPub)}');
    expect(envX[0], 1);
    expect(await enc.decryptFromPeer(envX, peer.xPriv), data);

    // ed25519:-tagged identity → sealed to mapped u → opens with the
    // x25519 seed derived from the ed seed.
    final envE = await enc.encryptForPeer(data, 'ed25519:${_hex(peer.edPub)}');
    expect(await enc.decryptFromPeer(envE, peer.xPriv), data);
  });
}
