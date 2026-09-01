import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/dataset_media_service.dart';

void main() {
  group('Dataset Media Parser Tests', () {
    late DatasetMediaService datasetService;

    setUp(() {
      datasetService = DatasetMediaService();
    });

    test('parses Parquet magic header', () {
      final header = Uint8List.fromList([0x50, 0x41, 0x52, 0x31]); // "PAR1"
      final meta = datasetService.parseParquetHeader(header);
      expect(meta.isValid, isTrue);
      expect(meta.compressionCodec, equals('SNAPPY'));
    });

    test('parses FITS astronomy header card', () {
      final fitsCard =
          'SIMPLE  =                    T / file does conform to FITS standard             '
              .padRight(80);
      final meta = datasetService
          .parseFitsHeader(Uint8List.fromList(fitsCard.codeUnits));
      expect(meta.isValid, isTrue);
      expect(meta.naxis, equals(2));
      expect(meta.dimensions, equals([1024, 1024]));
    });
  });
}
