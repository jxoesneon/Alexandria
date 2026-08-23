import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/pluggable_transport_service.dart';

void main() {
  group('Pluggable Transport Tests', () {
    late PluggableTransportService service;

    setUp(() {
      service = PluggableTransportService();
    });

    test('obfuscates and deobfuscates TLS camouflage profile', () {
      service.setProfile(ObfuscationProfile.tlsCamouflage);
      final raw = Uint8List.fromList('Alexandria P2P Payload Data'.codeUnits);
      final obfuscated = service.obfuscate(raw);

      expect(obfuscated.length, greaterThan(raw.length));
      final recovered = service.deobfuscate(obfuscated);
      expect(recovered, equals(raw));
    });
  });
}
