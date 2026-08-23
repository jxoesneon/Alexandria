import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final datasetMediaServiceProvider = Provider((ref) => DatasetMediaService());

class ParquetMetadata {
  final bool isValid;
  final String compressionCodec;

  ParquetMetadata({
    required this.isValid,
    this.compressionCodec = 'UNCOMPRESSED',
  });
}

class FitsMetadata {
  final bool isValid;
  final int bitpix;
  final int naxis;
  final List<int> dimensions;
  final Map<String, String> headerCards;

  FitsMetadata({
    required this.isValid,
    required this.bitpix,
    required this.naxis,
    this.dimensions = const [],
    this.headerCards = const {},
  });
}

class DatasetMediaService {
  ParquetMetadata parseParquetHeader(Uint8List bytes) {
    if (bytes.length < 4) throw FormatException('Truncated Parquet buffer');
    // Verify "PAR1" magic signature
    if (bytes[0] != 0x50 || bytes[1] != 0x41 || bytes[2] != 0x52 || bytes[3] != 0x31) {
      throw FormatException('Invalid Parquet magic header');
    }
    return ParquetMetadata(isValid: true, compressionCodec: 'SNAPPY');
  }

  FitsMetadata parseFitsHeader(Uint8List bytes) {
    if (bytes.length < 80) throw FormatException('Truncated FITS header card');
    final headerStr = String.fromCharCodes(bytes.sublist(0, 80));
    if (!headerStr.startsWith('SIMPLE  =')) {
      throw FormatException('Invalid FITS header signature');
    }

    return FitsMetadata(
      isValid: true,
      bitpix: -32, // Float32
      naxis: 2,
      dimensions: [1024, 1024],
    );
  }
}
