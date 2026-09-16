import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/pluggable_transport_service.dart';

void main() {
  group('PluggableTransportService (test/services)', () {
    late PluggableTransportService service;

    setUp(() {
      service = PluggableTransportService();
    });

    test('provider exposes a service instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(pluggableTransportServiceProvider),
        isA<PluggableTransportService>(),
      );
    });

    test('default profile is tlsCamouflage and setProfile updates it', () {
      expect(service.currentProfile, equals(ObfuscationProfile.tlsCamouflage));
      service.setProfile(ObfuscationProfile.none);
      expect(service.currentProfile, equals(ObfuscationProfile.none));
    });

    test('none profile is an identity transform', () {
      service.setProfile(ObfuscationProfile.none);
      final raw = Uint8List.fromList('plain text'.codeUnits);
      expect(service.obfuscate(raw), equals(raw));
      expect(service.deobfuscate(raw), equals(raw));
    });

    test('TLS camouflage roundtrip', () {
      service.setProfile(ObfuscationProfile.tlsCamouflage);
      final raw = Uint8List.fromList('TLS hidden payload'.codeUnits);
      final obfuscated = service.obfuscate(raw);

      expect(obfuscated.length, greaterThan(raw.length));
      expect(obfuscated.sublist(0, 3), equals([0x17, 0x03, 0x03]));
      expect(service.deobfuscate(obfuscated), equals(raw));
    });

    test('Shadowsocks AEAD roundtrip', () {
      service.setProfile(ObfuscationProfile.shadowsocksAead);
      final raw = Uint8List.fromList('Shadowsocks payload'.codeUnits);
      final obfuscated = service.obfuscate(raw);

      // Wire: salt(16) ‖ mask, where mask = base64(nonce(16) ‖ ct ‖
      // tag(32)) XOR salt — i.e. 16 + base64Len(48 + len). The base64
      // armor + salt mask is cosmetic; security lives in the keyed
      // keystream + HMAC tag (round-2 fix — the old profile was
      // salt ‖ plaintext⊕salt with no key material at all).
      final frameLen = 48 + raw.length;
      final base64Len = 4 * ((frameLen + 2) ~/ 3);
      expect(obfuscated.length, equals(16 + base64Len));
      expect(service.deobfuscate(obfuscated), equals(raw));
    });

    test('obfs4 entropy roundtrip', () {
      service.setProfile(ObfuscationProfile.obfs4Entropy);
      final raw = Uint8List.fromList('obfs4 payload'.codeUnits);
      final obfuscated = service.obfuscate(raw);

      expect(obfuscated.length, greaterThan(raw.length));
      expect(service.deobfuscate(obfuscated), equals(raw));
    });

    test('TLS deobfuscate throws on truncated record', () {
      service.setProfile(ObfuscationProfile.tlsCamouflage);
      final short = Uint8List.fromList([0x17, 0x03, 0x03]);
      expect(() => service.deobfuscate(short), throwsFormatException);
    });

    test('TLS deobfuscate throws on invalid header', () {
      service.setProfile(ObfuscationProfile.tlsCamouflage);
      final bad =
          Uint8List.fromList([0x16, 0x03, 0x03, 0x00, 0x05, 1, 2, 3, 4, 5]);
      expect(() => service.deobfuscate(bad), throwsFormatException);
    });

    test('TLS deobfuscate throws on length mismatch', () {
      service.setProfile(ObfuscationProfile.tlsCamouflage);
      // Header claims 100 bytes but only 2 follow
      final bad = Uint8List.fromList([0x17, 0x03, 0x03, 0x00, 100, 1, 2]);
      expect(() => service.deobfuscate(bad), throwsFormatException);
    });

    test('Shadowsocks deobfuscate throws on truncated payload', () {
      service.setProfile(ObfuscationProfile.shadowsocksAead);
      final short = Uint8List(15);
      expect(() => service.deobfuscate(short), throwsFormatException);
    });

    test('obfs4 deobfuscate throws on empty payload', () {
      service.setProfile(ObfuscationProfile.obfs4Entropy);
      expect(() => service.deobfuscate(Uint8List(0)), throwsFormatException);
    });

    test('obfs4 deobfuscate throws on truncated frame', () {
      service.setProfile(ObfuscationProfile.obfs4Entropy);
      // padLen 50, but no bytes follow
      final bad = Uint8List.fromList([50]);
      expect(() => service.deobfuscate(bad), throwsFormatException);
    });
  });
}
