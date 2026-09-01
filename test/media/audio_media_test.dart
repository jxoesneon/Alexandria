import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/audio_media_service.dart';

void main() {
  group('Audio & Music Media Parser Tests', () {
    late AudioMediaService audioService;

    setUp(() {
      audioService = AudioMediaService();
    });

    test('parses FLAC audio stream header correctly', () {
      final header = Uint8List(42);
      header[0] = 0x66; // 'f'
      header[1] = 0x4C; // 'L'
      header[2] = 0x61; // 'a'
      header[3] = 0x43; // 'C'
      header[18] = (44100 >> 12) & 0xFF;
      header[19] = (44100 >> 4) & 0xFF;
      header[20] =
          ((44100 & 0x0F) << 4) | (1 << 1) | 0x00; // 2 channels, 16 bits

      final info = audioService.parseFlacHeader(header);
      expect(info.sampleRate, equals(44100));
      expect(info.channels, equals(2));
    });

    test('rejects truncated FLAC buffers', () {
      expect(() => audioService.parseFlacHeader(Uint8List(10)),
          throwsFormatException);
    });
  });
}
