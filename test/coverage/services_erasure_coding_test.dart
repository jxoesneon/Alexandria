import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/erasure_coding_service.dart';

void main() {
  group('ErasureCodingService coverage extras', () {
    late ErasureCodingService service;

    setUp(() {
      service = ErasureCodingService();
    });

    test('provider exposes a service instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(erasureCodingServiceProvider),
          isA<ErasureCodingService>());
    });

    test('ErasureShard serializes to JSON and back', () {
      final shard = ErasureShard(
        index: 3,
        isParity: true,
        data: Uint8List.fromList([1, 2, 3, 4]),
        checksum: 'abc123',
      );
      final json = shard.toJson();
      expect(json['index'], 3);
      expect(json['isParity'], isTrue);
      expect(json['data'], [1, 2, 3, 4]);
      expect(json['checksum'], 'abc123');

      final restored = ErasureShard.fromJson(json);
      expect(restored.index, 3);
      expect(restored.isParity, isTrue);
      expect(restored.data, Uint8List.fromList([1, 2, 3, 4]));
      expect(restored.checksum, 'abc123');
    });

    test('ErasureBlock serializes to JSON and back', () {
      final original =
          Uint8List.fromList('Block serialization roundtrip'.codeUnits);
      final block = service.encode(blockId: 'blk-json', data: original);

      final json = block.toJson();
      expect(json['blockId'], 'blk-json');
      expect(json['originalSize'], original.length);
      expect(json['k'], 4);
      expect(json['m'], 2);
      expect((json['shards'] as List).length, 6);

      final restored = ErasureBlock.fromJson(json);
      expect(restored.blockId, 'blk-json');
      expect(restored.originalSize, original.length);
      expect(restored.k, 4);
      expect(restored.m, 2);
      expect(restored.shardSize, block.shardSize);
      expect(restored.shards.length, 6);
      expect(restored.shards.first.isParity, isFalse);
      expect(restored.shards.last.isParity, isTrue);
    });

    test('encode rejects an empty payload with ArgumentError', () {
      expect(
        () => service.encode(blockId: 'blk-empty', data: Uint8List(0)),
        throwsArgumentError,
      );
    });

    test('decode rejects malformed block parameters', () {
      final block = ErasureBlock(
        blockId: 'bad',
        originalSize: 10,
        k: 0,
        m: 1,
        shardSize: 4,
        shards: const [],
      );
      expect(() => service.decode(block: block, availableShards: const []),
          throwsStateError);

      final oversized = ErasureBlock(
        blockId: 'bad2',
        originalSize: 10,
        k: 200,
        m: 60, // k + m > 255
        shardSize: 4,
        shards: const [],
      );
      expect(() => service.decode(block: oversized, availableShards: const []),
          throwsStateError);
    });

    test('decode rejects malformed block sizes', () {
      ErasureBlock bad({
        required int originalSize,
        required int shardSize,
      }) =>
          ErasureBlock(
            blockId: 'bad',
            originalSize: originalSize,
            k: 4,
            m: 2,
            shardSize: shardSize,
            shards: const [],
          );

      expect(
          () => service.decode(
              block: bad(originalSize: 10, shardSize: 0),
              availableShards: const []),
          throwsStateError);
      expect(
          () => service.decode(
              block: bad(originalSize: -1, shardSize: 4),
              availableShards: const []),
          throwsStateError);
      // originalSize > k * shardSize is inflated and must fail closed.
      expect(
          () => service.decode(
              block: bad(originalSize: 100, shardSize: 4),
              availableShards: const []),
          throwsStateError);
    });

    test('decode drops out-of-range, duplicate, truncated, and bad-checksum shards',
        () {
      final original = Uint8List.fromList(
          'Shard hygiene: first valid claim wins'.codeUnits);
      final block = service.encode(blockId: 'blk-hygiene', data: original);

      final forged = <ErasureShard>[
        // Out-of-range index (>= k + m)
        ErasureShard(
          index: 99,
          isParity: false,
          data: Uint8List(block.shardSize),
          checksum: 'x',
        ),
        // Negative index
        ErasureShard(
          index: -1,
          isParity: false,
          data: Uint8List(block.shardSize),
          checksum: 'x',
        ),
        // Truncated payload
        ErasureShard(
          index: 0,
          isParity: false,
          data: Uint8List(1),
          checksum: 'x',
        ),
        // Corrupt checksum on an in-range index — dropped, so the REAL
        // shard 0 later in the list still counts (first *valid* claim).
        ErasureShard(
          index: 1,
          isParity: false,
          data: block.shards[1].data,
          checksum: 'deliberately-wrong',
        ),
      ];

      final available = <ErasureShard>[...forged, ...block.shards];
      final decoded =
          service.decode(block: block, availableShards: available);
      expect(decoded, equals(original));
    });

    test('decode with only forged shards fails closed', () {
      final original = Uint8List.fromList('Nothing valid here'.codeUnits);
      final block = service.encode(blockId: 'blk-forged', data: original);

      final forgedOnly = block.shards
          .take(6)
          .map((s) => ErasureShard(
                index: s.index,
                isParity: s.isParity,
                data: s.data,
                checksum: 'forged',
              ))
          .toList();
      expect(
          () => service.decode(block: block, availableShards: forgedOnly),
          throwsStateError);
    });
  });
}
