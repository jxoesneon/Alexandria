import 'dart:developer' as dev;
import 'dart:typed_data';
import 'package:alexandria/services/erasure_coding_service.dart';

void main() {
  final service = ErasureCodingService();
  final data = Uint8List(1024 * 1024); // 1 MB
  for (var i = 0; i < data.length; i++) {
    data[i] = i % 256;
  }

  final sw = Stopwatch()..start();
  final block = service.encode(blockId: 'bench_1', data: data, k: 4, m: 2);
  sw.stop();
  dev.log('Cauchy RS Encode (1MB, k=4, m=2): ${sw.elapsedMilliseconds} ms');

  sw.reset();
  sw.start();
  final recovered =
      service.decode(block: block, availableShards: block.shards.sublist(0, 4));
  sw.stop();
  dev.log(
      'Cauchy RS Decode (1MB, k=4): ${sw.elapsedMilliseconds} ms, bytes: ${recovered.length}');
}
