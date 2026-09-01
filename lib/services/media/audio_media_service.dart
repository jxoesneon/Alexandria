import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final audioMediaServiceProvider = Provider((ref) => AudioMediaService());

class FlacStreamInfo {
  final int minBlockSize;
  final int maxBlockSize;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int totalSamples;

  FlacStreamInfo({
    required this.minBlockSize,
    required this.maxBlockSize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.totalSamples,
  });

  double get durationSeconds =>
      totalSamples > 0 && sampleRate > 0 ? totalSamples / sampleRate : 0.0;
}

class AudioMediaService {
  FlacStreamInfo parseFlacHeader(Uint8List bytes) {
    if (bytes.length < 42) throw const FormatException('Truncated FLAC buffer');
    // Verify "fLaC" magic marker
    if (bytes[0] != 0x66 ||
        bytes[1] != 0x4C ||
        bytes[2] != 0x61 ||
        bytes[3] != 0x43) {
      throw const FormatException('Invalid FLAC magic marker');
    }

    final minBlock = (bytes[8] << 8) | bytes[9];
    final maxBlock = (bytes[10] << 8) | bytes[11];
    final sampleRate = (bytes[18] << 12) | (bytes[19] << 4) | (bytes[20] >> 4);
    final channels = ((bytes[20] >> 1) & 0x07) + 1;
    final bitsPerSample = (((bytes[20] & 0x01) << 4) | (bytes[21] >> 4)) + 1;

    var totalSamples = 0;
    for (var i = 22; i < 26; i++) {
      totalSamples = (totalSamples << 8) | bytes[i];
    }

    return FlacStreamInfo(
      minBlockSize: minBlock,
      maxBlockSize: maxBlock,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      totalSamples: totalSamples,
    );
  }
}
