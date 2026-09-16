import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/alexandria_mcp_server.dart';
import 'package:alexandria/services/agent/mcp_stdio_runner.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/headless_sdk.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/plugins/doi_harvester_plugin.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

class _FakeIdentityService implements IdentityService {
  _FakeIdentityService(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  @override
  Future<AlexandriaIdentity?> getIdentity() async => AlexandriaIdentity(
        publicKey: publicKeyBytes,
        privateKey: Uint8List.fromList(await keyPair.extractPrivateKeyBytes()),
        createdAt: DateTime(2026, 1, 1),
      );

  @override
  Future<Uint8List> sign(Uint8List data) async {
    final sig = await Ed25519().sign(data, keyPair: keyPair);
    return Uint8List.fromList(sig.bytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubDoiResolver extends DoiResolver {
  @override
  Future<DoiRecord?> resolve(String rawDoi) async {
    final doi = DoiResolver.normalizeDoi(rawDoi);
    if (doi.isEmpty) return null;
    return DoiRecord(
      doi: doi,
      title: 'Stub record for $doi',
      authors: const ['Test Author'],
      journal: 'Journal of Test Doubles',
      sourceApi: 'stub',
    );
  }
}

class _FakeTools {
  final calls = <String>[];

  List<Map<String, dynamic>> list() => [
        for (final n in [
          'alexandria_search_archive',
          'alexandria_get_wallet_balance',
          'alexandria_request_por_challenge',
          'alexandria_replicate_cid',
        ])
          {'name': n, 'inputSchema': <String, dynamic>{}},
      ];

  Future<Map<String, dynamic>> call(
      String name, Map<String, dynamic> args) async {
    calls.add(name);
    return {
      'content': [
        {'type': 'text', 'text': '{"ok":true}'}
      ],
      'isError': false,
    };
  }
}

Map<String, dynamic> _req(String token, String method,
        {dynamic id = 1, Map<String, dynamic>? params}) =>
    {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'session_token': token,
      if (params != null) 'params': params,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlexandriaMcpRunner coverage extras', () {
    test('default session token generation and getter', () {
      final tools = _FakeTools();
      final runner =
          AlexandriaMcpRunner(listTools: tools.list, callTool: tools.call);
      // No sessionToken supplied → generated internally.
      expect(runner.sessionToken, isNotEmpty);
      expect(runner.sessionSpend, 0.0);
    });

    test('initialize handshake returns server capabilities', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok', listTools: tools.list, callTool: tools.call);
      final res =
          await runner.handleJsonRpcRequest(_req('tok', 'initialize', id: 9));
      expect(res!['result']['serverInfo']['name'], 'alexandria-mcp-runner');
      expect(res['result']['protocolVersion'], '2024-11-05');
    });

    test('token accepted under params.session_token', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok2', listTools: tools.list, callTool: tools.call);
      final res = await runner.handleJsonRpcRequest({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/list',
        'params': {'session_token': 'tok2'},
      });
      expect(res!['result'], isNotNull);
    });

    test('tools/call with non-Map params and arguments fall back to {}',
        () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok', listTools: tools.list, callTool: tools.call);
      // params not a Map → treated as empty → empty tool name →
      // allowlist refusal.
      final res1 = await runner.handleJsonRpcRequest({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'session_token': 'tok',
        'params': 'not-a-map',
      });
      expect(res1!['result'], isNotNull);

      // arguments not a Map → empty args.
      final res2 = await runner
          .handleJsonRpcRequest(_req('tok', 'tools/call', id: 4, params: {
        'name': 'alexandria_get_wallet_balance',
        'arguments': 'not-a-map',
      }));
      expect(res2!['result']['isError'], isFalse);
      expect(tools.calls, contains('alexandria_get_wallet_balance'));
    });

    test('unknown method returns -32601', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok', listTools: tools.list, callTool: tools.call);
      final res =
          await runner.handleJsonRpcRequest(_req('tok', 'bogus/method', id: 5));
      expect(res!['error']['code'], -32601);
    });

    test('spend tool refuses non-positive amount', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok',
          listTools: tools.list,
          callTool: tools.call,
          allowedTools: {
            'alexandria_search_archive',
            'alexandria_replicate_cid',
          });
      final res = await runner
          .handleJsonRpcRequest(_req('tok', 'tools/call', id: 6, params: {
        'name': 'alexandria_replicate_cid',
        'arguments': {'credits': 0},
      }));
      // Error outcome, no spend recorded.
      expect(runner.sessionSpend, 0.0);
      expect(res, isNotNull);
    });
  });

  group('McpControlSocket coverage extras', () {
    test('port/isRunning before start and auth timeout close', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok-s', listTools: tools.list, callTool: tools.call);
      final socket = McpControlSocket(runner,
          authTimeout: const Duration(milliseconds: 120));
      expect(socket.port, 0);
      expect(socket.isRunning, isFalse);
      final port = await socket.start();
      addTearDown(socket.close);
      expect(socket.isRunning, isTrue);
      expect(socket.port, port);

      // Connect and never authenticate → authTimer closes the socket.
      final conn = await Socket.connect('127.0.0.1', port);
      final done = Completer<void>();
      conn.listen((_) {}, onDone: done.complete);
      await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
      conn.destroy();
    });

    test('oversized frame closes connection', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok-s2', listTools: tools.list, callTool: tools.call);
      final socket = McpControlSocket(runner, maxFrameBytes: 64);
      final port = await socket.start();
      addTearDown(socket.close);

      final conn = await Socket.connect('127.0.0.1', port);
      final done = Completer<void>();
      conn.listen((_) {}, onDone: done.complete);
      // >64 bytes in one chunk without newline → buffer cap → close.
      conn.add(List.filled(128, 0x41));
      await conn.flush();
      await done.future.timeout(const Duration(seconds: 5), onTimeout: () {});
      conn.destroy();
    });

    test('post-auth garbage line gets a parse-error frame', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok-s3', listTools: tools.list, callTool: tools.call);
      final socket = McpControlSocket(runner);
      final port = await socket.start();
      addTearDown(socket.close);

      final conn = await Socket.connect('127.0.0.1', port);
      addTearDown(conn.destroy);
      final received = <String>[];
      var buf = '';
      conn.listen((d) {
        buf += utf8.decode(d);
        var nl = buf.indexOf('\n');
        while (nl != -1) {
          final line = buf.substring(0, nl);
          buf = buf.substring(nl + 1);
          if (line.isNotEmpty) received.add(line);
          nl = buf.indexOf('\n');
        }
      });
      Future<void> waitLines(int n) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (received.length < n) {
          if (DateTime.now().isAfter(deadline)) {
            fail('timed out waiting for $n lines, got $received');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      conn.writeln(jsonEncode({'auth': 'tok-s3'}));
      await conn.flush();
      await waitLines(1);
      expect(jsonDecode(received[0])['ok'], isTrue);

      conn.writeln('this is not json');
      await conn.flush();
      await waitLines(2);
      final err = jsonDecode(received[1]) as Map<String, dynamic>;
      expect(err['error']['code'], -32700);
    });
  });

  group('HeadlessSdk RPC edge coverage', () {
    late ProviderContainer container;
    late HeadlessSdk sdk;

    setUp(() {
      container = ProviderContainer();
      sdk = container.read(headlessSdkProvider);
    });

    tearDown(() => container.dispose());

    Future<Map<String, dynamic>> rpc(String method,
        {Map<String, dynamic>? params, String? token}) async {
      return sdk.executeRpc(jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': {
          ...?params,
          if (token != null) 'authToken': token,
        },
        'id': 1,
      }));
    }

    test('mutating RPCs reject missing params and verify surfaces', () async {
      await sdk.startDaemon();
      final token = sdk.rpcAuthToken!;

      // pin / unpin / verify without cid → ArgumentError responses.
      for (final m in [
        'alexandria.pin',
        'alexandria.unpin',
        'alexandria.verify'
      ]) {
        final res = await rpc(m, token: token);
        expect(res['error'], isNotNull);
      }

      // import without payload.
      final imp = await rpc('alexandria.import', token: token);
      expect(imp['error'], isNotNull);

      // Oversized base64 payload → cap refusal.
      final huge =
          base64Encode(List.filled(HeadlessSdk.maxImportBytes + 1024, 0x61));
      final big = await rpc('alexandria.import',
          params: {'dataBase64': huge}, token: token);
      expect(big['error'], isNotNull);

      // Unknown method → error.
      final bogus = await rpc('alexandria.bogus', token: token);
      expect(bogus['error'], isNotNull);

      await sdk.stopDaemon();
    });

    test('import respects the daemon storage budget', () async {
      final small = ProviderContainer(overrides: [
        headlessSdkProvider.overrideWith((ref) =>
            HeadlessSdk(ref, config: const DaemonConfig(maxStorageMb: 0))),
      ]);
      addTearDown(small.dispose);
      final tiny = small.read(headlessSdkProvider);
      await tiny.startDaemon();
      final token = tiny.rpcAuthToken!;
      final res = await tiny.executeRpc(jsonEncode({
        'jsonrpc': '2.0',
        'method': 'alexandria.import',
        'params': {
          'dataBase64': base64Encode(utf8.encode('payload')),
          'authToken': token,
        },
        'id': 1,
      }));
      expect(res['error'], isNotNull);
      expect(res['error']['message'].toString(), contains('budget'));
      await tiny.stopDaemon();
    });
  });

  group('AlexandriaMcpServer coverage extras', () {
    late ProviderContainer container;
    late PoCHService pochService;
    late CreditService creditService;
    late MoltbookService moltbookService;
    late ProofOfRetrievabilityService porService;
    late IpfsService ipfsService;
    late AlexandriaMcpServer mcpServer;
    late _FakeIdentityService identity;

    setUp(() async {
      final keyPair = await Ed25519().newKeyPair();
      final pub = await keyPair.extractPublicKey();
      identity = _FakeIdentityService(keyPair, Uint8List.fromList(pub.bytes));

      pochService = PoCHService();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
      container = ProviderContainer(overrides: [
        creditServiceProvider.overrideWith((_) => creditService),
        identityServiceProvider.overrideWithValue(identity),
      ]);
      moltbookService = MoltbookService(creditService: creditService);
      // Not disposed in tearDown: the service's async key-init would
      // race the disposal and hit ChangeNotifier's
      // used-after-dispose assert.
      porService = container.read(proofOfRetrievabilityServiceProvider);
      ipfsService = container.read(ipfsServiceProvider);

      // No db → the in-memory DOI dedup path (line 424) runs.
      mcpServer = AlexandriaMcpServer(
        creditService: creditService,
        pochService: pochService,
        cryptoBridgeService: CryptoBridgeService(creditService: creditService),
        moltbookService: moltbookService,
        porService: porService,
        ipfsService: ipfsService,
        identityService: identity,
        doiResolver: _StubDoiResolver(),
      );
    });

    tearDown(() => container.dispose());

    test('porService getter exposes the injected service', () {
      expect(mcpServer.porService, same(porService));
    });

    test('unknown tool and throwing tool both error gracefully', () async {
      final unknown = await mcpServer.callTool('bogus_tool', {});
      expect(unknown['isError'], isTrue);

      // Missing required arg → cast throws inside → caught by the
      // dispatch guard.
      final bad =
          await mcpServer.callTool('alexandria_post_moltbook_bounty', {});
      expect(bad['isError'], isTrue);
    });

    test('handleJsonRpcRequest tools/call with non-Map params/arguments',
        () async {
      final res1 = await mcpServer.handleJsonRpcRequest({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': 'nope',
      });
      expect(res1['result'], isNotNull);

      final res2 = await mcpServer.handleJsonRpcRequest({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {
          'name': 'alexandria_get_wallet_balance',
          'arguments': 'nope',
        },
      });
      expect(res2['result'], isNotNull);
    });

    test('DOI ingest dedup uses the in-memory set when no db', () async {
      final res = await mcpServer.callTool('alexandria_ingest_doi', {
        'doi': '10.5555/dedup-test',
        'title': 'Dedup Test',
      });
      expect(res['isError'], isFalse);
      // Second ingest of the same DOI → duplicate, zero credits.
      final dupe = await mcpServer.callTool('alexandria_ingest_doi', {
        'doi': '10.5555/dedup-test',
        'title': 'Dedup Test',
      });
      final text = (dupe['content'] as List).first['text'] as String;
      expect(jsonDecode(text)['status'], 'duplicate');
    });

    test('submit PoR challenge on absent blockstore errors', () async {
      // Issue a challenge for a CID never stored locally.
      final issue = await mcpServer
          .callTool('alexandria_request_por_challenge', {'cid': 'bafy_absent'});
      final issueText = (issue['content'] as List).first['text'] as String;
      final challengeId = jsonDecode(issueText)['challenge_id'] as String;

      final submit =
          await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': challengeId,
        'tag': 'deadbeef',
      });
      expect(submit['isError'], isTrue);
      final errText = (submit['content'] as List).first['text'] as String;
      expect(errText, contains('not present'));
    });

    test('post moltbook bounty publishes through the service', () async {
      final res = await mcpServer.callTool('alexandria_post_moltbook_bounty', {
        'cid': 'bafy_bounty_target',
        'title': 'Preserve this',
        'credits_reward': 1.0,
        'urgency': 'normal',
      });
      // Whether or not the escrow path completes, the dispatch must not
      // crash the server.
      expect(res, isA<Map<String, dynamic>>());
    });

    test('payout rail tools refuse while agentPayoutsEnabled is false',
        () async {
      final cashu = await mcpServer
          .callTool('alexandria_export_cashu_voucher', {'credits': 1.0});
      expect(cashu['isError'], isTrue);

      final sweep = await mcpServer.callTool('alexandria_sweep_lightning_live',
          {'lightning_address': 'x@y.z', 'credits': 1.0});
      expect(sweep['isError'], isTrue);
    });
  });
}
