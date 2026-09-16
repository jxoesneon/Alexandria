// RED TEAM PoC — ErasureCodingService trusts serialized shard/block
// metadata completely and crashes (or allocates unboundedly) on
// adversarial input.
//
// lib/services/erasure_coding_service.dart:
//   * decode() line 211: `fullGenMatrix[shardIdx]` indexes the
//     (k+m)-row generator matrix with an attacker-controlled
//     `ErasureShard.index` — an index ≥ k+m or < 0 throws an uncaught
//     RangeError (not the handled StateError), crashing remote-shard
//     processing.
//   * decode() line 223: `selectedShards[j].data[byteIdx]` assumes
//     every shard has block.shardSize bytes — a forged shard with a
//     SHORT data array and a *valid self-consistent checksum* crashes
//     the loop with RangeError.
//   * decode() lines 205/234: `raw.sublist(0, block.originalSize)`
//     trusts a wire-supplied originalSize — inflated/negative values
//     throw RangeError.
//   * encode() line 120 validates only k>0/m>0 — GF(256) cannot
//     represent >255 shard rows; k+m ≥ 256 makes log[x^y] index a
//     256-entry table out of bounds mid-encode.
//
// Asserts the SECURE expectation: malformed wire metadata must be
// rejected with a controlled error, never an uncaught crash. Failure
// marks remote-triggerable crash surface.
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/erasure_coding_service.dart';

ErasureShard _shard(int index, List<int> data, {bool parity = false}) =>
    ErasureShard(
      index: index,
      isParity: parity,
      data: Uint8List.fromList(data),
      checksum: sha256.convert(data).toString(), // VALID checksum
    );

void main() {
  final svc = ErasureCodingService();

  test('shard index outside the generator matrix must fail controlled',
      () {
    // k=2,m=1 → generator matrix has 3 rows. Attacker supplies a shard
    // at index 9 with a perfectly valid checksum — checksum proves
    // only self-consistency, never provenance.
    final block = ErasureBlock(
      blockId: 'b1',
      originalSize: 4,
      k: 2,
      m: 1,
      shardSize: 2,
      shards: [],
    );
    final forged = [
      _shard(0, [1, 2]),
      _shard(9, [3, 4], parity: true), // out-of-range index
    ];

    expect(
      () => svc.decode(block: block, availableShards: forged),
      throwsA(isA<StateError>()),
      reason:
          'index 9 indexed fullGenMatrix[9] on a 3-row matrix → '
          'uncaught RangeError; forged shard indices must be rejected '
          'before matrix selection',
    );
  });

  test('short shard data must fail controlled, not RangeError mid-loop',
      () {
    final block = ErasureBlock(
      blockId: 'b2',
      originalSize: 6,
      k: 3,
      m: 1,
      shardSize: 4, // declared 4
      shards: [],
    );
    final forged = [
      _shard(0, [1, 2, 3, 4]),
      _shard(1, [5]), // 1 byte, valid checksum, declared shardSize=4
      _shard(3, [9, 9, 9, 9], parity: true),
    ];

    expect(
      () => svc.decode(block: block, availableShards: forged),
      throwsA(isA<StateError>()),
      reason:
          'a 1-byte shard reaches data[byteIdx] with byteIdx up to '
          'shardSize-1 → RangeError inside the reconstruction loop; '
          'shard length must be validated against block.shardSize',
    );
  });

  test('inflated originalSize must fail controlled', () {
    final block = ErasureBlock(
      blockId: 'b3',
      originalSize: 1 << 30, // 1 GiB claimed for a 4-byte payload
      k: 2,
      m: 1,
      shardSize: 2,
      shards: [],
    );
    final shards = [
      _shard(0, [65, 66]),
      _shard(1, [67, 68]),
    ];
    expect(
      () => svc.decode(block: block, availableShards: shards),
      throwsA(isA<StateError>()),
      reason:
          'raw.sublist(0, 1<<30) on a 4-byte buffer → RangeError; '
          'originalSize must be bounded by k*shardSize before slicing',
    );
  });

  test('encode must reject parameters GF(256) cannot represent', () {
    // k+m ≥ 256 overflows the GF log/exp tables (256 entries) inside
    // _buildCauchyMatrix — GF256.log[x^y] with x^y ≥ 256 is a raw
    // index-out-of-range, and duplicate x^y columns silently produce
    // a singular/invalid matrix. NOTE: RangeError IS an ArgumentError
    // subtype, so the secure expectation must exclude it explicitly.
    Object? thrown;
    try {
      svc.encode(blockId: 'b4', data: Uint8List(512), k: 250, m: 10);
    } catch (e) {
      thrown = e;
    }
    expect(thrown, isNotNull);
    expect(thrown, isA<ArgumentError>(),
        reason: 'parameter rejection should be an ArgumentError');
    expect(thrown, isNot(isA<RangeError>()),
        reason:
            'k+m=260 reached GF256.log[x^y] with x^y ≥ 256 → uncaught '
            'RangeError from the field tables; encode must bound-check '
            'k+m ≤ 255 BEFORE touching the matrix');
  });
}
