import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/alexandria_mcp_server.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

void main() {
  group('AlexandriaMcpServer Tool Suite Tests (ALX-006 §5)', () {
    late ProviderContainer container;
    late PoCHService pochService;
    late CreditService creditService;
    late CryptoBridgeService cryptoBridgeService;
    late MoltbookService moltbookService;
    late ProofOfRetrievabilityService porService;
    late AlexandriaMcpServer mcpServer;

    setUp(() {
      container = ProviderContainer();
      pochService = PoCHService();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
      cryptoBridgeService = CryptoBridgeService(creditService: creditService);
      moltbookService = MoltbookService(creditService: creditService);
      porService = container.read(proofOfRetrievabilityServiceProvider);

      mcpServer = AlexandriaMcpServer(
        creditService: creditService,
        pochService: pochService,
        cryptoBridgeService: cryptoBridgeService,
        moltbookService: moltbookService,
        porService: porService,
      );
    });

    test('lists 8 registered MCP tools with input schemas', () {
      final tools = mcpServer.listTools();
      expect(tools.length, 8);

      final names = tools.map((t) => t['name'] as String).toList();
      expect(names, contains('alexandria_search_archive'));
      expect(names, contains('alexandria_ingest_doi'));
      expect(names, contains('alexandria_get_wallet_balance'));
      expect(names, contains('alexandria_replicate_cid'));
      expect(names, contains('alexandria_submit_por_challenge'));
      expect(names, contains('alexandria_post_moltbook_bounty'));
      expect(names, contains('alexandria_export_cashu_voucher'));
      expect(names, contains('alexandria_sweep_lightning_live'));

      for (final tool in tools) {
        expect(tool['inputSchema'], isNotNull);
        expect(tool['description'], isNotEmpty);
      }
    });

    test('executes alexandria_search_archive tool', () async {
      final res = await mcpServer.callTool('alexandria_search_archive', {'query': 'Physics'});
      expect(res['isError'], isFalse);

      final text = (res['content'] as List).first['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;
      expect(data['query'], 'Physics');
      expect(data['total_matches'], greaterThan(0));
    });

    test('executes alexandria_ingest_doi tool and awards verification credits', () async {
      final initialBalance = creditService.balance;

      final res = await mcpServer.callTool('alexandria_ingest_doi', {
        'doi': '10.1038/nature12373',
        'title': 'Quantum teleportation between distant matter qubits',
      });

      expect(res['isError'], isFalse);
      final text = (res['content'] as List).first['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;
      expect(data['status'], 'success');
      expect(data['assigned_cid'], contains('10.1038'));
      expect(creditService.balance, initialBalance + 15.0);

      // Rejects invalid DOI prefix
      final invalidRes = await mcpServer.callTool('alexandria_ingest_doi', {'doi': 'invalid_doi_format'});
      expect(invalidRes['isError'], isTrue);
    });

    test('executes alexandria_get_wallet_balance tool', () async {
      final res = await mcpServer.callTool('alexandria_get_wallet_balance', {});
      expect(res['isError'], isFalse);

      final text = (res['content'] as List).first['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;
      expect(data['balance_credits'], creditService.balance);
      expect(data['poch_score'], isNotNull);
      expect(data['bandwidth_qos_multiplier'], isNotNull);
    });

    test('executes alexandria_replicate_cid tool with credit deduction', () async {
      final initialBalance = creditService.balance;

      final res = await mcpServer.callTool('alexandria_replicate_cid', {
        'cid': 'bafk_endangered_dataset_1',
        'credits': 20.0,
      });

      expect(res['isError'], isFalse);
      expect(creditService.balance, initialBalance - 20.0);

      // Fails when exceeding balance
      final excessRes = await mcpServer.callTool('alexandria_replicate_cid', {
        'cid': 'bafk_excess',
        'credits': 1000.0,
      });
      expect(excessRes['isError'], isTrue);
    });

    test('executes alexandria_submit_por_challenge tool', () async {
      final initialBalance = creditService.balance;

      final res = await mcpServer.callTool('alexandria_submit_por_challenge', {
        'cid': 'bafk_sample_cid',
        'challenge_nonce': 'nonce_valid_123',
      });

      expect(res['isError'], isFalse);
      expect(creditService.balance, greaterThan(initialBalance));

      // Rejects short nonce
      final failRes = await mcpServer.callTool('alexandria_submit_por_challenge', {
        'cid': 'bafk_sample_cid',
        'challenge_nonce': 'short',
      });
      expect(failRes['isError'], isTrue);
    });

    test('executes alexandria_export_cashu_voucher tool', () async {
      final res = await mcpServer.callTool('alexandria_export_cashu_voucher', {
        'credits': 10.0,
      });

      expect(res['isError'], isFalse);
      final text = (res['content'] as List).first['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;
      expect(data['cashu_token'].toString().startsWith('cashuA'), isTrue);
      expect(data['sats_equivalent'], 100);
    });

    test('handles JSON-RPC 2.0 dispatch for tools/list and tools/call', () async {
      // 1. tools/list
      final listRpc = await mcpServer.handleJsonRpcRequest({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
      });
      expect(listRpc['jsonrpc'], '2.0');
      expect(listRpc['id'], 1);
      expect(listRpc['result']['tools'].length, 8);

      // 2. tools/call
      final callRpc = await mcpServer.handleJsonRpcRequest({
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {
          'name': 'alexandria_get_wallet_balance',
          'arguments': {},
        },
      });
      expect(callRpc['id'], 2);
      expect(callRpc['result']['isError'], isFalse);

      // 3. unknown method error code -32601
      final errRpc = await mcpServer.handleJsonRpcRequest({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'unknown/method',
      });
      expect(errRpc['error']['code'], -32601);
    });

    test('executes alexandria_sweep_lightning_live tool with validation', () async {
      // Rejects invalid address
      final errRes = await mcpServer.callTool('alexandria_sweep_lightning_live', {
        'lightning_address': 'not_an_email',
        'credits': 10.0,
      });
      expect(errRes['isError'], isTrue);
    });
  });
}
