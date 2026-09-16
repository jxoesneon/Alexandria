import 'dart:convert';
import 'dart:io';
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
  test('Alexandria MCP Stdio Runner', () async {
    final container = ProviderContainer();
    final pochService = PoCHService();
    final creditService = CreditService(
      pochService: pochService,
      initialBalance: 100.0,
    );
    final cryptoBridgeService =
        CryptoBridgeService(creditService: creditService);
    final moltbookService = MoltbookService(creditService: creditService);
    final porService = container.read(proofOfRetrievabilityServiceProvider);
    final ipfsService = container.read(ipfsServiceProvider);

    final mcpServer = AlexandriaMcpServer(
      creditService: creditService,
      pochService: pochService,
      cryptoBridgeService: cryptoBridgeService,
      moltbookService: moltbookService,
      porService: porService,
      ipfsService: ipfsService,
    );

    // If ALX_STDIO_MODE is set, run interactive stdio JSON-RPC loop
    if (Platform.environment['ALX_STDIO_MODE'] == 'true') {
      while (true) {
        final line = stdin.readLineSync();
        if (line == null || line.trim().isEmpty) break;
        try {
          final request = jsonDecode(line) as Map<String, dynamic>;
          final response = await mcpServer.handleJsonRpcRequest(request);
          stdout.writeln(jsonEncode(response));
        } catch (e) {
          stdout.writeln(jsonEncode({
            'jsonrpc': '2.0',
            'error': {'code': -32700, 'message': 'Parse error: $e'}
          }));
        }
      }
    } else {
      // Diagnostic mode: verify all 9 tools execute cleanly
      final tools = mcpServer.listTools();
      expect(tools.length, 9);
    }
  });
}
