// RED TEAM PoC - HeadlessSdk.executeRpc (lib/services/headless_sdk.dart)
// dispatches mutating RPC methods with:
//   * NO liveness gate - calls execute even when the daemon was never
//     started (`_isRunning == false`); 'alexandria.status' correctly
//     reports 'stopped' while 'alexandria.import' happily writes.
//   * NO size cap - 'alexandria.import' base64-decodes attacker input
//     into memory and ipfs.addFile() stores + PINS it forever
//     (addFile adds to _pinnedCids, so runGc can never reclaim it):
//     unbounded memory growth via RPC.
//   * NO authentication - if/when a transport binds this dispatcher
//     (rpcPort 9099 in DaemonConfig), every call above is remote.
//
// Asserts the SECURE expectation: a stopped daemon must refuse RPC
// dispatch, and import must bound payload size.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/headless_sdk.dart';
import 'package:alexandria/services/ipfs_service.dart';

void main() {
  late ProviderContainer container;
  late HeadlessSdk sdk;

  setUp(() {
    container = ProviderContainer();
    sdk = container.read(headlessSdkProvider);
  });
  tearDown(() => container.dispose());

  test('RPC must refuse dispatch while the daemon is stopped', () async {
    expect(sdk.isRunning, isFalse);
    final res = await sdk.executeRpc(jsonEncode({
      'method': 'alexandria.import',
      'params': {'dataBase64': base64Encode(utf8.encode('x'))},
      'id': 1,
    }));
    expect(res['error'], isNotNull,
        reason: 'alexandria.import executed on a STOPPED daemon — the RPC '
            'dispatcher has no liveness gate, so the RPC surface is '
            'live even when the node is "off".');
  });

  test(
      'alexandria.import must bound payload size (unbounded + '
      'auto-pin = memory exhaustion)', () async {
    await sdk.startDaemon();
    final ipfs = container.read(ipfsServiceProvider);
    final before = ipfs.storedBytes;

    final payload = base64Encode(Uint8List(8 << 20)); // 8 MiB
    final res = await sdk.executeRpc(jsonEncode({
      'method': 'alexandria.import',
      'params': {'dataBase64': payload},
      'id': 2,
    }));

    expect(res['error'], isNotNull,
        reason: 'an 8 MiB import was accepted with no size cap; storedBytes '
            'grew ${ipfs.storedBytes - before} and the block is pinned '
            '(addFile auto-pins) so GC can never reclaim it — an '
            'unauthenticated RPC caller can grow memory without bound.');
  });
}
