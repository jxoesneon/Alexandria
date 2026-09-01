import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final spatialMediaServiceProvider = Provider((ref) => SpatialMediaService());

class GlbMetadata {
  final int version;
  final int byteLength;
  final int jsonLength;
  final bool hasAnimations;

  GlbMetadata({
    required this.version,
    required this.byteLength,
    required this.jsonLength,
    this.hasAnimations = false,
  });
}

class SpatialMediaService {
  GlbMetadata parseGlbHeader(Uint8List bytes) {
    if (bytes.length < 20) throw const FormatException('Truncated GLB buffer');
    // "glTF" magic 0x46546C67
    if (bytes[0] != 0x67 ||
        bytes[1] != 0x6C ||
        bytes[2] != 0x54 ||
        bytes[3] != 0x46) {
      throw const FormatException('Invalid glTF GLB binary signature');
    }

    final version =
        bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24);
    final length =
        bytes[8] | (bytes[9] << 8) | (bytes[10] << 16) | (bytes[11] << 24);
    final jsonChunkLen =
        bytes[12] | (bytes[13] << 8) | (bytes[14] << 16) | (bytes[15] << 24);

    return GlbMetadata(
      version: version,
      byteLength: length,
      jsonLength: jsonChunkLen,
      hasAnimations: false,
    );
  }
}
