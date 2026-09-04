import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/fast_cdc_service.dart';

void main() {
  group('FastCdcService coverage', () {
    test('FastCdcConfig uses the documented defaults', () {
      const config = FastCdcConfig();
      expect(config.minSize, 2048);
      expect(config.avgSize, 8192);
      expect(config.maxSize, 32768);
    });

    test('Chunk serializes to JSON without data payload', () {
      final chunk = Chunk(
        offset: 0,
        length: 64,
        hash: 'sha256-digest',
        data: Uint8List.fromList(List.generate(64, (i) => i)),
      );
      final json = chunk.toJson();
      expect(json['offset'], 0);
      expect(json['length'], 64);
      expect(json['hash'], 'sha256-digest');
      expect(json.containsKey('data'), isFalse);
    });

    test('returns empty list for empty input', () {
      const config = FastCdcConfig(minSize: 64, avgSize: 256, maxSize: 1024);
      final service = FastCdcService(config: config);
      expect(service.chunk(Uint8List(0)), isEmpty);
    });

    test('chunks small data below the minimum as a single chunk', () {
      const config = FastCdcConfig(minSize: 64, avgSize: 256, maxSize: 1024);
      final service = FastCdcService(config: config);
      final data = Uint8List.fromList(List.generate(32, (i) => i));
      final chunks = service.chunk(data);

      expect(chunks.length, 1);
      expect(chunks.single.length, 32);
      expect(chunks.single.offset, 0);
      expect(chunks.single.hash, isNotEmpty);
      expect(chunks.single.data.length, 32);
    });

    test('reconstructs input for deterministic data with default config', () {
      final service = FastCdcService();
      final data = Uint8List.fromList(List.generate(20000, (i) => i % 256));
      final chunks = service.chunk(data);

      var total = 0;
      for (final c in chunks) {
        total += c.length;
      }
      expect(total, data.length);

      final reconstructed = BytesBuilder();
      for (final c in chunks) {
        reconstructed.add(c.data);
      }
      expect(reconstructed.toBytes(), data);
    });

    test('produces identical chunks for identical content', () {
      const config = FastCdcConfig(minSize: 64, avgSize: 256, maxSize: 1024);
      final serviceA = FastCdcService(config: config);
      final serviceB = FastCdcService(config: config);
      final data = Uint8List.fromList(utf8.encode('x' * 4096));

      final chunksA = serviceA.chunk(data);
      final chunksB = serviceB.chunk(data);

      expect(chunksA.length, chunksB.length);
      for (var i = 0; i < chunksA.length; i++) {
        expect(chunksA[i].length, chunksB[i].length);
        expect(chunksA[i].hash, chunksB[i].hash);
      }
    });

    test('stays within min and max chunk sizes for random data', () {
      const config = FastCdcConfig(minSize: 64, avgSize: 256, maxSize: 1024);
      final service = FastCdcService(config: config);
      final data = Uint8List.fromList(
        List.generate(10000, (i) => (i * 73) % 256),
      );
      final chunks = service.chunk(data);

      expect(chunks, isNotEmpty);
      var total = 0;
      for (final c in chunks) {
        expect(c.length, greaterThanOrEqualTo(1));
        expect(c.length, lessThanOrEqualTo(config.maxSize));
        total += c.length;
      }
      expect(total, data.length);
    });
  });
}
