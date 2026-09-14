import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/agent/alexandria_mcp_server.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

void main() {
  group('AlexandriaMcpServer Tool Suite Tests (ALX-006 §5)', () {
    late ProviderContainer container;
    late PoCHService pochService;
    late CreditService creditService;
    late CryptoBridgeService cryptoBridgeService;
    late MoltbookService moltbookService;
    late ProofOfRetrievabilityService porService;
    late IpfsService ipfsService;
    late AlexandriaMcpServer mcpServer;

    setUp(() {
      pochService = PoCHService();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
      // verifyProof mints through the container's creditServiceProvider —
      // override it so the award lands on the instance under test.
      container = ProviderContainer(overrides: [
        creditServiceProvider.overrideWith((_) => creditService),
      ]);
      cryptoBridgeService = CryptoBridgeService(creditService: creditService);
      moltbookService = MoltbookService(creditService: creditService);
      porService = container.read(proofOfRetrievabilityServiceProvider);
      ipfsService = container.read(ipfsServiceProvider);

      mcpServer = AlexandriaMcpServer(
        creditService: creditService,
        pochService: pochService,
        cryptoBridgeService: cryptoBridgeService,
        moltbookService: moltbookService,
        porService: porService,
        ipfsService: ipfsService,
      );
    });

    test('lists 9 registered MCP tools with input schemas', () {
      final tools = mcpServer.listTools();
      expect(tools.length, 9);

      final names = tools.map((t) => t['name'] as String).toList();
      expect(names, contains('alexandria_search_archive'));
      expect(names, contains('alexandria_ingest_doi'));
      expect(names, contains('alexandria_get_wallet_balance'));
      expect(names, contains('alexandria_replicate_cid'));
      expect(names, contains('alexandria_request_por_challenge'));
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

      // Re-ingesting the same DOI pays nothing (ALX-010 dedupe)
      final dupeRes = await mcpServer.callTool('alexandria_ingest_doi', {
        'doi': '10.1038/nature12373',
      });
      expect(dupeRes['isError'], isFalse);
      final dupeData = jsonDecode(
          (dupeRes['content'] as List).first['text'] as String) as Map<String, dynamic>;
      expect(dupeData['status'], 'duplicate');
      expect(dupeData['credits_earned'], 0.0);
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

    test('executes real PoR challenge round-trip (ALX-010)', () async {
      // Store a payload so the CID exists in the local blockstore
      final payload = Uint8List.fromList(
          utf8.encode('endangered scientific payload for por audit'));
      final cid = await ipfsService.addFile(payload);
      final initialBalance = creditService.balance;

      // 1. Request a fresh challenge
      final challengeRes = await mcpServer
          .callTool('alexandria_request_por_challenge', {'cid': cid});
      expect(challengeRes['isError'], isFalse);
      final challengeData = jsonDecode((challengeRes['content'] as List)
          .first['text'] as String) as Map<String, dynamic>;
      final challengeId = challengeData['challenge_id'] as String;
      final nonceHex = challengeData['nonce_hex'] as String;

      // 2. Compute the tag the prover would produce
      final nonceBytes = Uint8List.fromList(List.generate(
          nonceHex.length ~/ 2,
          (i) => int.parse(nonceHex.substring(i * 2, i * 2 + 2), radix: 16)));
      final tag = Hmac(sha256, nonceBytes).convert(payload).toString();

      // 3. Submit — verifies, mints via verifyProof internally
      final res = await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': challengeId,
        'tag': tag,
      });
      expect(res['isError'], isFalse);
      expect(creditService.balance, greaterThan(initialBalance));

      // 4. A wrong tag is rejected — no payout
      final challenge2 = await mcpServer
          .callTool('alexandria_request_por_challenge', {'cid': cid});
      final id2 = jsonDecode((challenge2['content'] as List)
          .first['text'] as String)['challenge_id'] as String;
      final failRes = await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': id2,
        'tag': 'deadbeef' * 8,
      });
      expect(failRes['isError'], isTrue);

      // 5. A fabricated challenge ID is rejected outright
      final forgedRes = await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': 'forged_id_12345',
        'tag': tag,
      });
      expect(forgedRes['isError'], isTrue);
    });

    test('agent payout rails are disabled until attestation (ALX-010)', () async {
      final res = await mcpServer.callTool('alexandria_export_cashu_voucher', {
        'credits': 10.0,
      });
      expect(res['isError'], isTrue);

      final sweepRes = await mcpServer.callTool('alexandria_sweep_lightning_live', {
        'lightning_address': 'agent@walletofsatoshi.com',
        'credits': 10.0,
      });
      expect(sweepRes['isError'], isTrue);
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
      expect(listRpc['result']['tools'].length, 9);

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
      // Disabled rail rejects before address validation (ALX-010)
      final errRes = await mcpServer.callTool('alexandria_sweep_lightning_live', {
        'lightning_address': 'not_an_email',
        'credits': 10.0,
      });
      expect(errRes['isError'], isTrue);
    });
  });
}
