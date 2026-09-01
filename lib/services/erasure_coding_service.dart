import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final erasureCodingServiceProvider = Provider((ref) => ErasureCodingService());

class GF256 {
  static final Uint8List exp = Uint8List(512);
  static final Uint8List log = Uint8List(256);

  static void init() {
    var x = 1;
    for (var i = 0; i < 255; i++) {
      exp[i] = x;
      exp[i + 255] = x;
      log[x] = i;
      x <<= 1;
      if (x >= 256) x ^= 0x11D;
    }
    log[0] = 0;
  }

  static int mul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return exp[log[a] + log[b]];
  }

  static int div(int a, int b) {
    if (b == 0) throw ArgumentError('Division by zero in GF(256)');
    if (a == 0) return 0;
    return exp[log[a] - log[b] + 255];
  }

  static int add(int a, int b) => a ^ b;
  static int sub(int a, int b) => a ^ b;
}

class ErasureShard {
  final int index;
  final bool isParity;
  final Uint8List data;
  final String checksum;

  ErasureShard({
    required this.index,
    required this.isParity,
    required this.data,
    required this.checksum,
  });

  bool verifyChecksum() {
    final actual = sha256.convert(data).toString();
    return actual == checksum;
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'isParity': isParity,
        'data': data.toList(),
        'checksum': checksum,
      };

  factory ErasureShard.fromJson(Map<String, dynamic> json) => ErasureShard(
        index: json['index'] as int,
        isParity: json['isParity'] as bool,
        data: Uint8List.fromList(List<int>.from(json['data'] as List)),
        checksum: json['checksum'] as String,
      );
}

class ErasureBlock {
  final String blockId;
  final int originalSize;
  final int k;
  final int m;
  final int shardSize;
  final List<ErasureShard> shards;

  ErasureBlock({
    required this.blockId,
    required this.originalSize,
    required this.k,
    required this.m,
    required this.shardSize,
    required this.shards,
  });

  Map<String, dynamic> toJson() => {
        'blockId': blockId,
        'originalSize': originalSize,
        'k': k,
        'm': m,
        'shardSize': shardSize,
        'shards': shards.map((s) => s.toJson()).toList(),
      };

  factory ErasureBlock.fromJson(Map<String, dynamic> json) => ErasureBlock(
        blockId: json['blockId'] as String,
        originalSize: json['originalSize'] as int,
        k: json['k'] as int,
        m: json['m'] as int,
        shardSize: json['shardSize'] as int,
        shards: (json['shards'] as List)
            .map((s) => ErasureShard.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

class ErasureCodingService {
  ErasureCodingService() {
    GF256.init();
  }

  ErasureBlock encode({
    required String blockId,
    required Uint8List data,
    int k = 4,
    int m = 2,
  }) {
    if (k <= 0 || m <= 0) throw ArgumentError('k and m must be positive');
    final originalSize = data.length;
    final shardSize = (originalSize + k - 1) ~/ k;
    final dataShards = List.generate(k, (i) => Uint8List(shardSize));

    for (var i = 0; i < k; i++) {
      final start = i * shardSize;
      if (start < originalSize) {
        final end = (start + shardSize > originalSize)
            ? originalSize
            : start + shardSize;
        dataShards[i].setRange(0, end - start, data.sublist(start, end));
      }
    }

    final matrix = _buildCauchyMatrix(k, m);
    final parityShards = List.generate(m, (i) => Uint8List(shardSize));

    for (var i = 0; i < m; i++) {
      for (var byteIdx = 0; byteIdx < shardSize; byteIdx++) {
        var val = 0;
        for (var j = 0; j < k; j++) {
          val = GF256.add(val, GF256.mul(matrix[i][j], dataShards[j][byteIdx]));
        }
        parityShards[i][byteIdx] = val;
      }
    }

    final allShards = <ErasureShard>[];
    for (var i = 0; i < k; i++) {
      allShards.add(ErasureShard(
        index: i,
        isParity: false,
        data: dataShards[i],
        checksum: sha256.convert(dataShards[i]).toString(),
      ));
    }
    for (var i = 0; i < m; i++) {
      allShards.add(ErasureShard(
        index: k + i,
        isParity: true,
        data: parityShards[i],
        checksum: sha256.convert(parityShards[i]).toString(),
      ));
    }

    return ErasureBlock(
      blockId: blockId,
      originalSize: originalSize,
      k: k,
      m: m,
      shardSize: shardSize,
      shards: allShards,
    );
  }

  Uint8List decode({
    required ErasureBlock block,
    required List<ErasureShard> availableShards,
  }) {
    final validShards =
        availableShards.where((s) => s.verifyChecksum()).toList();
    if (validShards.length < block.k) {
      throw StateError(
          'Insufficient valid shards to decode. Required: ${block.k}, Available: ${validShards.length}');
    }

    validShards.sort((a, b) => a.index.compareTo(b.index));
    final selectedShards = validShards.take(block.k).toList();

    var allDataPresent = true;
    for (var i = 0; i < block.k; i++) {
      if (!selectedShards.any((s) => s.index == i)) {
        allDataPresent = false;
        break;
      }
    }

    if (allDataPresent) {
      final out = BytesBuilder();
      for (var i = 0; i < block.k; i++) {
        final s = selectedShards.firstWhere((element) => element.index == i);
        out.add(s.data);
      }
      final raw = out.toBytes();
      return raw.sublist(0, block.originalSize);
    }

    final fullGenMatrix = _buildFullGeneratorMatrix(block.k, block.m);
    final subMatrix = List.generate(block.k, (i) {
      final shardIdx = selectedShards[i].index;
      return List<int>.from(fullGenMatrix[shardIdx]);
    });

    final invMatrix = _invertMatrix(subMatrix, block.k);
    final reconstructedDataShards =
        List.generate(block.k, (_) => Uint8List(block.shardSize));

    for (var i = 0; i < block.k; i++) {
      for (var byteIdx = 0; byteIdx < block.shardSize; byteIdx++) {
        var val = 0;
        for (var j = 0; j < block.k; j++) {
          val = GF256.add(
              val, GF256.mul(invMatrix[i][j], selectedShards[j].data[byteIdx]));
        }
        reconstructedDataShards[i][byteIdx] = val;
      }
    }

    final out = BytesBuilder();
    for (var i = 0; i < block.k; i++) {
      out.add(reconstructedDataShards[i]);
    }
    final raw = out.toBytes();
    return raw.sublist(0, block.originalSize);
  }

  ErasureBlock repairShards({
    required ErasureBlock block,
    required List<ErasureShard> availableShards,
  }) {
    final recoveredData =
        decode(block: block, availableShards: availableShards);
    return encode(
        blockId: block.blockId, data: recoveredData, k: block.k, m: block.m);
  }

  List<List<int>> _buildCauchyMatrix(int k, int m) {
    return List.generate(m, (i) {
      return List.generate(k, (j) {
        final x = k + i;
        final y = j;
        return GF256.div(1, x ^ y);
      });
    });
  }

  List<List<int>> _buildFullGeneratorMatrix(int k, int m) {
    final matrix = List.generate(k + m, (i) => List.filled(k, 0));
    for (var i = 0; i < k; i++) {
      matrix[i][i] = 1;
    }
    final cauchy = _buildCauchyMatrix(k, m);
    for (var i = 0; i < m; i++) {
      for (var j = 0; j < k; j++) {
        matrix[k + i][j] = cauchy[i][j];
      }
    }
    return matrix;
  }

  List<List<int>> _invertMatrix(List<List<int>> mat, int n) {
    final aug = List.generate(n, (i) {
      final row = List.filled(2 * n, 0);
      for (var j = 0; j < n; j++) {
        row[j] = mat[i][j];
      }
      row[n + i] = 1;
      return row;
    });

    for (var i = 0; i < n; i++) {
      var pivot = aug[i][i];
      if (pivot == 0) {
        var swapIdx = -1;
        for (var r = i + 1; r < n; r++) {
          if (aug[r][i] != 0) {
            swapIdx = r;
            break;
          }
        }
        if (swapIdx == -1) {
          throw StateError('Singular matrix in erasure decoder');
        }
        final tmp = aug[i];
        aug[i] = aug[swapIdx];
        aug[swapIdx] = tmp;
        pivot = aug[i][i];
      }

      if (pivot != 1) {
        for (var j = 0; j < 2 * n; j++) {
          aug[i][j] = GF256.div(aug[i][j], pivot);
        }
      }

      for (var r = 0; r < n; r++) {
        if (r != i) {
          final factor = aug[r][i];
          if (factor != 0) {
            for (var j = 0; j < 2 * n; j++) {
              aug[r][j] = GF256.sub(aug[r][j], GF256.mul(factor, aug[i][j]));
            }
          }
        }
      }
    }

    return List.generate(n, (i) {
      return List.generate(n, (j) => aug[i][n + j]);
    });
  }
}
