import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/fast_cdc_service.dart';

void main() {
  group('FastCdcService Tests', () {
    late FastCdcService cdcService;

    setUp(() {
      cdcService = FastCdcService(
        config: const FastCdcConfig(minSize: 64, avgSize: 256, maxSize: 1024),
      );
    });

    test('returns empty list for empty data', () {
      expect(cdcService.chunk(Uint8List(0)), isEmpty);
    });

    test('chunks data within min and max boundaries', () {
      final sample = Uint8List.fromList(List.generate(4096, (i) => (i * 31) % 256));
      final chunks = cdcService.chunk(sample);

      expect(chunks.isNotEmpty, isTrue);
      var totalReconstructed = 0;
      for (final c in chunks) {
        expect(c.length, greaterThanOrEqualTo(64));
        expect(c.length, lessThanOrEqualTo(1024));
        totalReconstructed += c.length;
      }
      expect(totalReconstructed, equals(4096));
    });

    test('preserves identical hashes for identical content chunks', () {
      final dataA = Uint8List.fromList(List.generate(2048, (i) => i % 256));
      final dataB = Uint8List.fromList(List.generate(2048, (i) => i % 256));

      final chunksA = cdcService.chunk(dataA);
      final chunksB = cdcService.chunk(dataB);

      expect(chunksA.length, equals(chunksB.length));
      for (var i = 0; i < chunksA.length; i++) {
        expect(chunksA[i].hash, equals(chunksB[i].hash));
      }
    });
  });
}
