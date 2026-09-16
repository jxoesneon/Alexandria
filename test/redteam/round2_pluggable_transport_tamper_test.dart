// RED TEAM PoC — "Shadowsocks AEAD" is neither AEAD nor encryption.
//
// lib/services/pluggable_transport_service.dart:79-101 implements
// `shadowsocksAead` as salt ‖ (plaintext XOR repeating-salt), with the
// 16-byte salt prepended in CLEARTEXT. Consequences:
//   * Confidentiality: any observer reads the salt off the wire and
//     recovers the plaintext keystream directly — the "cipher" is
//     self-decrypting for anyone with the ciphertext.
//   * Integrity: there is no MAC/tag. A MITM flipping ciphertext bit i
//     predictably flips plaintext bit i and `deobfuscate` returns the
//     forged plaintext with NO error — a silent tampering channel for
//     anything routed over this profile.
//   * No key material exists at all: knowledge of the public profile
//     name fully decodes every frame.
//
// Asserts the SECURE expectation for a profile NAMED "aead": tampered
// ciphertext must be rejected and ciphertext must not be trivially
// decryptable by a passive observer.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/pluggable_transport_service.dart';

void main() {
  test('tampered ciphertext must be rejected (AEAD implies a tag)', () {
    final svc = PluggableTransportService()
      ..setProfile(ObfuscationProfile.shadowsocksAead);

    final plaintext = Uint8List.fromList(
        utf8.encode('{"action":"releaseEscrow","amount":1}'));
    final wire = svc.obfuscate(plaintext);

    // MITM: flip one bit inside the ciphertext region (after the
    // 16-byte salt prefix) to morph the JSON amount digit.
    final tampered = Uint8List.fromList(wire);
    tampered[16 + tampered.length - 18] ^= 0x01; // '1' -> '0'

    Object? thrown;
    Uint8List? out;
    try {
      out = svc.deobfuscate(tampered);
    } catch (e) {
      thrown = e;
    }

    expect(thrown, isNotNull,
        reason: 'bit-flipped "AEAD" ciphertext deobfuscated WITHOUT error to '
            '"${out == null ? null : utf8.decode(out)}" — no MAC means '
            'silent tampering on everything carried by this profile');
  });

  test('a passive observer must not recover plaintext from the wire', () {
    final svc = PluggableTransportService()
      ..setProfile(ObfuscationProfile.shadowsocksAead);

    final secret = utf8.encode('wallet-seed-phrase-top-secret');
    final wire = svc.obfuscate(Uint8List.fromList(secret));

    // Attacker with ONLY the wire bytes: salt = wire[0..16], keystream
    // = repeating salt. Reconstruct without calling any API.
    final salt = wire.sublist(0, 16);
    final recovered = Uint8List(wire.length - 16);
    for (var i = 0; i < recovered.length; i++) {
      recovered[i] = wire[16 + i] ^ salt[i % 16];
    }

    expect(utf8.decode(recovered), isNot(utf8.decode(secret)),
        reason: 'the salt is prepended in cleartext and there is no key — '
            'anyone holding the ciphertext recovers the plaintext '
            'exactly. This profile provides zero confidentiality.');
  });

  test('tlsCamouflage must at least reject trailing-garbage records', () {
    final svc = PluggableTransportService()
      ..setProfile(ObfuscationProfile.tlsCamouflage);
    final wire = svc.obfuscate(Uint8List.fromList(utf8.encode('hello')));

    // Append attacker junk: length field still says 5 so the reader
    // silently truncates and ignores the tail — the profile is a
    // framing wrapper, not TLS; a receiver must at minimum refuse a
    // record carrying MORE bytes than the declared length.
    final padded = Uint8List.fromList([...wire, 0xAA, 0xBB, 0xCC]);
    Object? thrown;
    try {
      svc.deobfuscate(padded);
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isNotNull,
        reason: 'trailing bytes beyond the declared length are silently '
            'discarded — a MITM can splice extra data into the stream '
            'with no detectable difference at the receiver');
  });
}
