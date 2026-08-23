import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/pluggable_transport_service.dart';

void main() {
  group('Pluggable Transport Security & Fuzzing', () {
    late PluggableTransportService transport;

    setUp(() {
      transport = PluggableTransportService();
    });

    test('handles TLS record camouflage and un-framing', () {
      transport.setProfile(ObfuscationProfile.tlsCamouflage);
      final payload = Uint8List.fromList('Resilient Transport Frame'.codeUnits);
      final obfuscated = transport.obfuscate(payload);

      expect(obfuscated[0], 0x17); // TLS Application Data
      final restored = transport.deobfuscate(obfuscated);
      expect(restored, equals(payload));
    });

    test('handles Shadowsocks AEAD salting and de-masking', () {
      transport.setProfile(ObfuscationProfile.shadowsocksAead);
      final payload = Uint8List.fromList('Masked Traffic Stream'.codeUnits);
      final obfuscated = transport.obfuscate(payload);

      expect(obfuscated.length, payload.length + 16);
      final restored = transport.deobfuscate(obfuscated);
      expect(restored, equals(payload));
    });
  });
}
