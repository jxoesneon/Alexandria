// MCP stdio runner tests (ALX-012 §5.2/§5.6): session-token auth on
// every request, read-only allowlist, per-tool rate budgets,
// spend ceilings + human-consent hook, the minting/receipt-ingest gate,
// and the authenticated loopback control socket.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/mcp_stdio_runner.dart';

/// Fake tool surface: records invocations and returns a success result.
class _FakeTools {
  final calls = <String>[];

  List<Map<String, dynamic>> list() => [
        for (final n in [
          'alexandria_search_archive',
          'alexandria_get_wallet_balance',
          'alexandria_request_por_challenge',
          'alexandria_ingest_doi',
          'alexandria_replicate_cid',
          'alexandria_submit_por_challenge',
          'alexandria_post_moltbook_bounty',
        ])
          {'name': n, 'inputSchema': <String, dynamic>{}},
      ];

  Future<Map<String, dynamic>> call(
      String name, Map<String, dynamic> args) async {
    calls.add(name);
    return {
      'content': [
        {'type': 'text', 'text': '{"ok":true,"tool":"$name"}'}
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
  group('AlexandriaMcpRunner session auth', () {
    test('session tokens are unique, non-empty CSPRNG strings', () {
      final a = AlexandriaMcpRunner.generateSessionToken();
      final b = AlexandriaMcpRunner.generateSessionToken();
      expect(a, isNotEmpty);
      expect(a, isNot(b));
    });

    test('every request without/with-wrong token is refused — including '
        'initialize and tools/list', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok-secret',
          listTools: tools.list,
          callTool: tools.call);

      for (final bad in [
        {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'},
        _req('wrong-token', 'initialize'),
        _req('', 'tools/list'),
        _req('wrong', 'tools/call',
            params: {'name': 'alexandria_search_archive'}),
      ]) {
        final res = await runner.handleJsonRpcRequest(bad);
        expect(res!['error']['code'], -32001);
      }
      // Nothing dispatched, nothing listed.
      expect(tools.calls, isEmpty);
    });

    test('token via params._meta.session_token is accepted', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok-meta',
          listTools: tools.list,
          callTool: tools.call);
      final res = await runner.handleJsonRpcRequest({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'ping',
        'params': {
          '_meta': {'session_token': 'tok-meta'}
        },
      });
      expect(res!['error'], isNull);
      expect(res['result'], isA<Map>());
    });
  });

  group('allowlist + rate budgets', () {
    test('tools/list advertises only the read-only allowlist', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 't', listTools: tools.list, callTool: tools.call);
      final res = await runner
          .handleJsonRpcRequest(_req('t', 'tools/list'));
      final listed = (res!['result']['tools'] as List)
          .map((t) => t['name'])
          .toList();
      expect(listed, unorderedEquals([
        'alexandria_search_archive',
        'alexandria_get_wallet_balance',
        'alexandria_request_por_challenge',
      ]));
    });

    test('non-allowlisted tool is refused before dispatch', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 't', listTools: tools.list, callTool: tools.call);
      final res = await runner.handleJsonRpcRequest(_req(
          't', 'tools/call',
          params: {'name': 'alexandria_replicate_cid', 'arguments': {}}));
      expect(res!['result']['isError'], isTrue);
      expect(tools.calls, isEmpty);
    });

    test('per-tool sliding-window budget is enforced independently',
        () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
        sessionToken: 't',
        listTools: tools.list,
        callTool: tools.call,
        rateBudgets: {
          'alexandria_search_archive':
              const McpRateBudget(maxCalls: 2, window: Duration(minutes: 1)),
        },
      );
      Future<Map<String, dynamic>?> call(String name) =>
          runner.handleJsonRpcRequest(_req('t', 'tools/call',
              params: {'name': name, 'arguments': {}}));

      expect((await call('alexandria_search_archive'))!['result']
          ['isError'], isFalse);
      expect((await call('alexandria_search_archive'))!['result']
          ['isError'], isFalse);
      // Third call inside the window → protocol-level rate error.
      final third = await call('alexandria_search_archive');
      expect(third!['error']['code'], -32029);
      // A different tool is unaffected — budgets are independent.
      expect((await call('alexandria_get_wallet_balance'))!['result']
          ['isError'], isFalse);
      expect(tools.calls,
          ['alexandria_search_archive', 'alexandria_search_archive',
           'alexandria_get_wallet_balance']);
    });

    test('minting/receipt-ingest tools stay refused unless the §5.2.4 '
        'gate is explicitly lifted', () async {
      final tools = _FakeTools();
      final gated = AlexandriaMcpRunner(
        sessionToken: 't',
        listTools: tools.list,
        callTool: tools.call,
        allowedTools: {'alexandria_ingest_doi'},
      );
      final res = await gated.handleJsonRpcRequest(_req(
          't', 'tools/call',
          params: {'name': 'alexandria_ingest_doi', 'arguments': {}}));
      expect(res!['result']['isError'], isTrue);
      expect(tools.calls, isEmpty);

      final open = AlexandriaMcpRunner(
        sessionToken: 't',
        listTools: tools.list,
        callTool: tools.call,
        allowedTools: {'alexandria_ingest_doi'},
        permitMintingTools: true,
      );
      final res2 = await open.handleJsonRpcRequest(_req(
          't', 'tools/call',
          params: {'name': 'alexandria_ingest_doi', 'arguments': {}}));
      expect(res2!['result']['isError'], isFalse);
    });
  });

  group('spend ceilings + human consent', () {
    AlexandriaMcpRunner econRunner(_FakeTools tools,
            {double ceiling = 50.0, McpConsentHook? consent}) =>
        AlexandriaMcpRunner(
          sessionToken: 't',
          listTools: tools.list,
          callTool: tools.call,
          allowedTools: {'alexandria_replicate_cid'},
          sessionSpendCeilingCredits: ceiling,
          consentHook: consent,
        );

    test('economic tool without a consent hook is refused even under '
        'the ceiling', () async {
      final tools = _FakeTools();
      final runner = econRunner(tools);
      final res = await runner.handleJsonRpcRequest(_req(
          't', 'tools/call',
          params: {
            'name': 'alexandria_replicate_cid',
            'arguments': {'cid': 'bafk_x', 'credits': 10.0}
          }));
      expect(res!['result']['isError'], isTrue);
      expect(tools.calls, isEmpty);
    });

    test('consent denial refuses the spend', () async {
      final tools = _FakeTools();
      var asked = 0;
      final runner =
          econRunner(tools, consent: (req) async {
        asked++;
        expect(req.toolName, 'alexandria_replicate_cid');
        expect(req.amountCredits, 10.0);
        return false;
      });
      final res = await runner.handleJsonRpcRequest(_req(
          't', 'tools/call',
          params: {
            'name': 'alexandria_replicate_cid',
            'arguments': {'cid': 'bafk_x', 'credits': 10.0}
          }));
      expect(res!['result']['isError'], isTrue);
      expect(asked, 1);
      expect(tools.calls, isEmpty);
      expect(runner.sessionSpend, 0.0);
    });

    test('approved spend executes and accumulates; exceeding the hard '
        'ceiling is refused even when consent approves', () async {
      final tools = _FakeTools();
      final runner = econRunner(tools,
          ceiling: 25.0, consent: (req) async => true);
      Future<bool> spend(double c) async {
        final res = await runner.handleJsonRpcRequest(_req(
            't', 'tools/call',
            params: {
              'name': 'alexandria_replicate_cid',
              'arguments': {'cid': 'bafk_x', 'credits': c}
            }));
        return res!['result']['isError'] == false;
      }

      expect(await spend(10.0), isTrue);
      expect(runner.sessionSpend, 10.0);
      expect(await spend(10.0), isTrue);
      expect(runner.sessionSpend, 20.0);
      // 20 + 10 > 25 → refused despite approval.
      expect(await spend(10.0), isFalse);
      expect(runner.sessionSpend, 20.0);
      expect(tools.calls.length, 2);
    });

    test('default ceiling of zero refuses all spend paths', () async {
      final tools = _FakeTools();
      final runner = econRunner(tools,
          ceiling: 0.0, consent: (req) async => true);
      final res = await runner.handleJsonRpcRequest(_req(
          't', 'tools/call',
          params: {
            'name': 'alexandria_replicate_cid',
            'arguments': {'cid': 'bafk_x', 'credits': 1.0}
          }));
      expect(res!['result']['isError'], isTrue);
      expect(tools.calls, isEmpty);
    });
  });

  group('McpControlSocket', () {
    test('loopback socket requires auth handshake, then still requires '
        'the per-request token', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok-sock',
          listTools: tools.list,
          callTool: tools.call);
      final socket = McpControlSocket(runner);
      final port = await socket.start();
      addTearDown(socket.close);
      expect(port, greaterThan(0));

      // Wrong auth → connection closed without a response frame.
      final bad = await Socket.connect('127.0.0.1', port);
      final badLines = <String>[];
      final badDone = Completer<void>();
      bad.listen((d) => badLines.addAll(
          utf8.decode(d).split('\n').where((l) => l.isNotEmpty)),
          onDone: badDone.complete);
      bad.writeln(jsonEncode({'auth': 'nope'}));
      await bad.flush();
      await badDone.future
          .timeout(const Duration(seconds: 5), onTimeout: () {});
      expect(badLines, isEmpty); // closed before any reply

      // Correct auth → {"ok":true}; then a tokenless request is refused
      // and a tokened request executes.
      final good = await Socket.connect('127.0.0.1', port);
      final received = <String>[];
      var sockBuf = '';
      good.listen((d) {
        // Frame across TCP chunk boundaries — buffer until '\n'.
        sockBuf += utf8.decode(d);
        var nl = sockBuf.indexOf('\n');
        while (nl != -1) {
          final line = sockBuf.substring(0, nl);
          sockBuf = sockBuf.substring(nl + 1);
          if (line.isNotEmpty) received.add(line);
          nl = sockBuf.indexOf('\n');
        }
      });
      Future<List<String>> waitLines(int n) async {
        final deadline =
            DateTime.now().add(const Duration(seconds: 5));
        while (received.length < n) {
          if (DateTime.now().isAfter(deadline)) {
            fail('timed out waiting for $n socket lines, got $received');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return received.take(n).toList();
      }

      good.writeln(jsonEncode({'auth': 'tok-sock'}));
      await good.flush();
      final hello = jsonDecode((await waitLines(1)).single) as Map;
      expect(hello['ok'], isTrue);

      good.writeln(jsonEncode(
          {'jsonrpc': '2.0', 'id': 7, 'method': 'ping'}));
      good.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'id': 8,
        'method': 'tools/call',
        'session_token': 'tok-sock',
        'params': {
          'name': 'alexandria_get_wallet_balance',
          'arguments': <String, dynamic>{}
        },
      }));
      await good.flush();

      final replies = (await waitLines(3))
          .skip(1)
          .map((l) => jsonDecode(l) as Map<String, dynamic>)
          .toList();
      final unauth = replies.firstWhere((r) => r['id'] == 7);
      expect(unauth['error']['code'], -32001);
      final authed = replies.firstWhere((r) => r['id'] == 8);
      expect(authed['result']['isError'], isFalse);
      expect(tools.calls, ['alexandria_get_wallet_balance']);
      good.destroy();
    });

    test('auth frame + request frame in ONE TCP chunk stay ordered — '
        'the request is not mistaken for a second auth attempt', () async {
      final tools = _FakeTools();
      final runner = AlexandriaMcpRunner(
          sessionToken: 'tok-batch',
          listTools: tools.list,
          callTool: tools.call);
      final socket = McpControlSocket(runner);
      final port = await socket.start();
      addTearDown(socket.close);

      final conn = await Socket.connect('127.0.0.1', port);
      addTearDown(conn.destroy);
      final received = <String>[];
      var sockBuf = '';
      conn.listen((d) {
        sockBuf += utf8.decode(d);
        var nl = sockBuf.indexOf('\n');
        while (nl != -1) {
          final line = sockBuf.substring(0, nl);
          sockBuf = sockBuf.substring(nl + 1);
          if (line.isNotEmpty) received.add(line);
          nl = sockBuf.indexOf('\n');
        }
      });
      Future<List<String>> waitLines(int n) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (received.length < n) {
          if (DateTime.now().isAfter(deadline)) {
            fail('timed out waiting for $n socket lines, got $received');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return received.take(n).toList();
      }

      // One write, two frames — this is the batching pattern the JS
      // bridge produces when stdin races the connect callback.
      conn.write('${jsonEncode({'auth': 'tok-batch'})}\n'
          '${jsonEncode(_req('tok-batch', 'ping', id: 42))}\n');
      await conn.flush();

      final lines = await waitLines(2);
      expect(jsonDecode(lines[0])['ok'], isTrue);
      final ping = jsonDecode(lines[1]) as Map<String, dynamic>;
      expect(ping['id'], 42);
      expect(ping['result'], isA<Map>());
      expect(conn.destroy, returnsNormally);
    });
  });
}
