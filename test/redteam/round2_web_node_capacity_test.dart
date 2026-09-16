// RED TEAM PoC — IndexedDbBlockStore.putBlock stores a block LARGER
// than the configured capacity.
//
// lib/services/web_node_service.dart:19-29 evicts in a `while` loop
// until the store is EMPTY, then stores the incoming block
// unconditionally. A single oversized block therefore evicts the
// entire shard cache AND lands anyway, leaving
// currentUsage > maxCapacityBytes — on a browser web-node this is a
// remote-triggerable IndexedDB quota exhaustion: every peer that can
// push a block can blow past the node's declared storage budget and
// wipe all previously held blocks (availability + resource attack).
//
// Asserts the SECURE expectation: a store must never exceed its own
// capacity bound. Failure marks a live capacity-enforcement bypass.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/web_node_service.dart';

void main() {
  test('single oversized block must be refused, not stored past capacity',
      () async {
    final store = IndexedDbBlockStore(maxCapacityBytes: 1024);

    // Legit content first.
    await store.putBlock('cid_a', Uint8List(400));
    await store.putBlock('cid_b', Uint8List(400));
    expect(store.currentUsage, 800);

    // Attacker pushes a 64 KiB block at a 1 KiB store.
    await store.putBlock('cid_evil', Uint8List(64 * 1024));

    expect(store.currentUsage, lessThanOrEqualTo(1024),
        reason:
            'a 64 KiB block was stored in a 1 KiB store — '
            'currentUsage=${store.currentUsage}, all prior blocks '
            'evicted AND the oversized block retained: remote quota '
            'exhaustion');
    expect(await store.hasBlock('cid_evil'), isFalse);
    // And the prior content must have survived.
    expect(await store.hasBlock('cid_a'), isTrue,
        reason: 'one oversized put wiped the entire block store');
  });

  test('eviction loop must bound total usage for normal blocks', () async {
    final store = IndexedDbBlockStore(maxCapacityBytes: 1000);
    for (var i = 0; i < 5; i++) {
      await store.putBlock('c$i', Uint8List(300));
    }
    expect(store.currentUsage, lessThanOrEqualTo(1000),
        reason: 'FIFO eviction failed to bound usage');
  });
}
