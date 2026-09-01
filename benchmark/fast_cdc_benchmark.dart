import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:alexandria/services/fast_cdc_service.dart';

void main() {
  final service = FastCdcService();
  final data = Uint8List(2 * 1024 * 1024); // 2 MB
  for (var i = 0; i < data.length; i++) {
    data[i] = (i * 37) % 256;
  }

  final sw = Stopwatch()..start();
  final chunks = service.chunk(data);
  sw.stop();
  dev.log(
      'FastCDC Chunking (2MB): ${sw.elapsedMilliseconds} ms, Total chunks: ${chunks.length}');
}
