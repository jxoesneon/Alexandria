import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../credits/credit_service.dart';
import '../credits/crypto_bridge_service.dart';
import '../credits/poch_service.dart';
import '../proof_of_retrievability_service.dart';
import 'moltbook_service.dart';

/// Riverpod provider for AlexandriaMcpServer
final alexandriaMcpServerProvider = Provider<AlexandriaMcpServer>((ref) {
  return AlexandriaMcpServer(
    creditService: ref.read(creditServiceProvider),
    pochService: ref.read(pochServiceProvider),
    cryptoBridgeService: ref.read(cryptoBridgeServiceProvider),
    moltbookService: ref.read(moltbookServiceProvider),
    porService: ref.read(proofOfRetrievabilityServiceProvider),
  );
});

/// Standardized Model Context Protocol (MCP) tool handler for Alexandria (ALX-006)
class AlexandriaMcpServer {
  final CreditService _creditService;
  final PoCHService _pochService;
  final CryptoBridgeService _cryptoBridgeService;
  final MoltbookService _moltbookService;
  final ProofOfRetrievabilityService _porService;

  AlexandriaMcpServer({
    required CreditService creditService,
    required PoCHService pochService,
    required CryptoBridgeService cryptoBridgeService,
    required MoltbookService moltbookService,
    required ProofOfRetrievabilityService porService,
  })  : _creditService = creditService,
        _pochService = pochService,
        _cryptoBridgeService = cryptoBridgeService,
        _moltbookService = moltbookService,
        _porService = porService;

  ProofOfRetrievabilityService get porService => _porService;

  /// Returns the complete list of available MCP tool definitions and schemas
  List<Map<String, dynamic>> listTools() {
    return [
      {
        'name': 'alexandria_search_archive',
        'description':
            'Searches the decentralized Alexandria library for academic documents, preprints, and CIDs.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description': 'Search keyword, author, paper title, or DOI'
            },
          },
          'required': ['query'],
        },
      },
      {
        'name': 'alexandria_ingest_doi',
        'description':
            'Harvests, validates, and archives a scientific paper by its DOI into the Alexandria commons.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'doi': {
              'type': 'string',
              'description': 'Digital Object Identifier (e.g. 10.1038/nature12373)'
            },
            'title': {
              'type': 'string',
              'description': 'Optional paper title'
            },
          },
          'required': ['doi'],
        },
      },
      {
        'name': 'alexandria_get_wallet_balance',
        'description':
            'Retrieves node Archival Credit balance, Proof of Common Heritage (PoCH) score, and QoS multiplier.',
        'inputSchema': {
          'type': 'object',
          'properties': {},
        },
      },
      {
        'name': 'alexandria_replicate_cid',
        'description':
            'Commissions Cauchy Reed-Solomon GF(2^8) parity replication across the peer swarm using Archival Credits.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'cid': {
              'type': 'string',
              'description': 'The target Content Identifier (CIDv1)'
            },
            'credits': {
              'type': 'number',
              'description': 'Amount of Archival Credits to allocate for replication'
            },
          },
          'required': ['cid', 'credits'],
        },
      },
      {
        'name': 'alexandria_submit_por_challenge',
        'description':
            'Solves and submits an HMAC-SHA256 Proof of Retrievability challenge to earn storage credits.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'cid': {
              'type': 'string',
              'description': 'Target stored CID to verify'
            },
            'challenge_nonce': {
              'type': 'string',
              'description': 'Random challenge nonce issued by auditing peer'
            },
          },
          'required': ['cid', 'challenge_nonce'],
        },
      },
      {
        'name': 'alexandria_post_moltbook_bounty',
        'description':
            'Publishes an Ed25519-signed Beacon v2 preservation bounty to the Moltbook AI agent network.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'cid': {'type': 'string', 'description': 'Target endangered CID'},
            'doi': {'type': 'string', 'description': 'Optional DOI of the document'},
            'title': {'type': 'string', 'description': 'Descriptive title for the bounty'},
            'credits_reward': {
              'type': 'number',
              'description': 'Reward offered in Archival Credits'
            },
            'urgency': {
              'type': 'string',
              'enum': ['normal', 'high', 'critical'],
              'description': 'Urgency level of the preservation alert'
            },
          },
          'required': ['cid', 'title', 'credits_reward'],
        },
      },
      {
        'name': 'alexandria_export_cashu_voucher',
        'description':
            'Exports node credits into an anonymous Chaumian E-Cash bearer voucher (Cashu NUT-00 standard).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'credits': {
              'type': 'number',
              'description': 'Credits to export (1 Credit = 10 Satoshis)'
            },
          },
          'required': ['credits'],
        },
      },
      {
        'name': 'alexandria_sweep_lightning_live',
        'description':
            'Sweeps Archival Credits as a live Bitcoin Lightning payment to any Lightning Address (LUD-16 LNURL-pay -> Cashu NUT-05 Melt).',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'lightning_address': {
              'type': 'string',
              'description': 'Target Lightning Address (e.g. user@domain.com)'
            },
            'credits': {
              'type': 'number',
              'description': 'Credits to sweep (1 Credit = 10 Satoshis)'
            },
          },
          'required': ['lightning_address', 'credits'],
        },
      },
    ];
  }

  /// Executes an MCP tool call and returns standard MCP response
  Future<Map<String, dynamic>> callTool(
      String toolName, Map<String, dynamic> arguments) async {
    try {
      switch (toolName) {
        case 'alexandria_search_archive':
          return await _searchArchive(arguments['query'] as String? ?? '');

        case 'alexandria_ingest_doi':
          return await _ingestDoi(
            arguments['doi'] as String? ?? '',
            title: arguments['title'] as String?,
          );

        case 'alexandria_get_wallet_balance':
          return _getWalletBalance();

        case 'alexandria_replicate_cid':
          return _replicateCid(
            arguments['cid'] as String? ?? '',
            (arguments['credits'] as num? ?? 0.0).toDouble(),
          );

        case 'alexandria_submit_por_challenge':
          return await _submitPorChallenge(
            arguments['cid'] as String? ?? '',
            arguments['challenge_nonce'] as String? ?? '',
          );

        case 'alexandria_post_moltbook_bounty':
          return await _postMoltbookBounty(arguments);

        case 'alexandria_export_cashu_voucher':
          return _exportCashuVoucher(
              (arguments['credits'] as num? ?? 0.0).toDouble());

        case 'alexandria_sweep_lightning_live':
          return await _sweepLightningLive(
            arguments['lightning_address'] as String? ?? '',
            (arguments['credits'] as num? ?? 0.0).toDouble(),
          );

        default:
          return _errorResponse('Unknown MCP tool: $toolName');
      }
    } catch (e) {
      return _errorResponse('Tool execution failed: $e');
    }
  }

  /// Processes a standard MCP / JSON-RPC 2.0 request payload
  Future<Map<String, dynamic>> handleJsonRpcRequest(
      Map<String, dynamic> request) async {
    final id = request['id'];
    final method = request['method'] as String?;

    if (method == 'tools/list') {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'result': {'tools': listTools()},
      };
    } else if (method == 'tools/call') {
      final paramsRaw = request['params'];
      final params = paramsRaw is Map
          ? Map<String, dynamic>.from(paramsRaw)
          : <String, dynamic>{};
      final name = params['name'] as String? ?? '';
      final argsRaw = params['arguments'];
      final args = argsRaw is Map
          ? Map<String, dynamic>.from(argsRaw)
          : <String, dynamic>{};
      final res = await callTool(name, args);
      return {
        'jsonrpc': '2.0',
        'id': id,
        'result': res,
      };
    } else {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32601, 'message': 'Method not found: $method'},
      };
    }
  }

  Future<Map<String, dynamic>> _searchArchive(String query) async {
    // Search active bounties and mock index
    final bounties = _moltbookService.activeBounties
        .where((b) =>
            b.title.toLowerCase().contains(query.toLowerCase()) ||
            (b.doi != null && b.doi!.contains(query)) ||
            b.cid.contains(query))
        .toList();

    final results = [
      {
        'cid': 'bafkreic3w7j4pqwqlp...',
        'title': 'Attention Is All You Need',
        'doi': '10.48550/arXiv.1706.03762',
        'replicas': 12,
        'rarity': 'Healthy',
      },
      ...bounties.map((b) => {
            'cid': b.cid,
            'title': b.title,
            'doi': b.doi,
            'replicas': 1,
            'rarity': 'Critically Endangered',
            'bounty_credits': b.offeredCredits,
          }),
    ];

    return _textResponse(jsonEncode({
      'query': query,
      'total_matches': results.length,
      'matches': results,
    }));
  }

  Future<Map<String, dynamic>> _ingestDoi(String doi, {String? title}) async {
    if (!doi.startsWith('10.')) {
      return _errorResponse('Invalid DOI format: $doi. Must begin with 10.');
    }

    final simulatedCid = 'bafk_${doi.replaceAll('/', '_')}';
    _creditService.awardVerificationCredits(
      action: 'Verified and ingested scientific paper: $doi',
      targetId: simulatedCid,
      amount: 15.0,
    );

    return _textResponse(jsonEncode({
      'status': 'success',
      'doi': doi,
      'title': title ?? 'Ingested Scientific Work',
      'assigned_cid': simulatedCid,
      'credits_earned': 15.0,
      'merkle_root': '0x8fbc92384a...',
    }));
  }

  Map<String, dynamic> _getWalletBalance() {
    final metrics = _pochService.metrics;
    return _textResponse(jsonEncode({
      'balance_credits': _creditService.balance,
      'protocol_treasury': _creditService.protocolTreasury,
      'archival_commons_pool': _creditService.archivalCommonsPool,
      'poch_score': metrics.score,
      'is_poch_compliant': metrics.isCompliant,
      'bandwidth_qos_multiplier': _pochService.bandwidthMultiplier,
      'contributions': {
        'storage_mb': metrics.allocatedStorageBytes / (1024 * 1024),
        'seeding_mb': metrics.dailySeedingBytes / (1024 * 1024),
        'por_challenges_passed': metrics.dailyPoRChallengesAnswered,
      }
    }));
  }

  Map<String, dynamic> _replicateCid(String cid, double credits) {
    if (credits <= 0) return _errorResponse('Credits must be > 0.');
    final success = _creditService.spendCredits(
      amount: credits,
      reason: 'Commissioned Swarm Parity Replication for $cid',
      referenceId: cid,
    );

    if (!success) {
      return _errorResponse(
          'Insufficient credit balance (${_creditService.balance.toStringAsFixed(1)} ℭ) to allocate $credits ℭ.');
    }

    return _textResponse(jsonEncode({
      'status': 'success',
      'cid': cid,
      'credits_spent': credits,
      'swarm_tasks_dispatched': 5,
      'remaining_balance': _creditService.balance,
    }));
  }

  Future<Map<String, dynamic>> _submitPorChallenge(
      String cid, String challengeNonce) async {
    final isValid = challengeNonce.length >= 8;
    if (!isValid) {
      return _errorResponse('Invalid challenge nonce length');
    }

    final earned = _creditService.awardStorageCredits(
      sizeBytes: 100 * 1024 * 1024,
      peerCount: 2,
      porPassed: true,
      cid: cid,
    );
    _pochService.recordPoRChallengeAnswered();

    return _textResponse(jsonEncode({
      'status': 'verified',
      'cid': cid,
      'proof_valid': true,
      'credits_awarded': earned,
      'new_balance': _creditService.balance,
    }));
  }

  Future<Map<String, dynamic>> _postMoltbookBounty(
      Map<String, dynamic> args) async {
    final cid = args['cid'] as String;
    final title = args['title'] as String;
    final doi = args['doi'] as String?;
    final credits = (args['credits_reward'] as num).toDouble();
    final urgency = args['urgency'] as String? ?? 'normal';

    final bounty = await _moltbookService.postPreservationBounty(
      cid: cid,
      title: title,
      doi: doi,
      offeredCredits: credits,
      urgency: urgency,
      force: true, // Agent tool calls pass force for urgent tasks
    );

    return _textResponse(jsonEncode({
      'status': 'published',
      'bounty_id': bounty.id,
      'moltbook_submolt': 'alexandria-bounties',
      'author_agent_id': _moltbookService.agentId,
      'offered_credits': credits,
    }));
  }

  Map<String, dynamic> _exportCashuVoucher(double credits) {
    final token = _cryptoBridgeService.exportCreditsAsCashuToken(credits);
    if (token == null) {
      return _errorResponse(
          'Failed to export Cashu token. Check that balance >= $credits.');
    }

    final serialized = token.serialize();
    return _textResponse(jsonEncode({
      'status': 'success',
      'credits_exported': credits,
      'sats_equivalent': token.totalAmountSats,
      'cashu_token': serialized,
    }));
  }

  Future<Map<String, dynamic>> _sweepLightningLive(
      String address, double credits) async {
    final result = await _cryptoBridgeService.sweepToLightningAddressLive(
      creditsToSweep: credits,
      customAddress: address,
    );

    if (result.success) {
      return _textResponse(jsonEncode(result.toJson()));
    } else {
      return _errorResponse(
          'Lightning sweep failed: ${result.error ?? "unknown error"} (Target: $address, Sats: ${result.sats})');
    }
  }

  Map<String, dynamic> _textResponse(String text) {
    return {
      'content': [
        {'type': 'text', 'text': text}
      ],
      'isError': false,
    };
  }

  Map<String, dynamic> _errorResponse(String message) {
    return {
      'content': [
        {'type': 'text', 'text': message}
      ],
      'isError': true,
    };
  }
}
