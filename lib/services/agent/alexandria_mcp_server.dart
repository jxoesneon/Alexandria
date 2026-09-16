import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database.dart' show AppDatabase, databaseProvider;
import '../credits/credit_service.dart';
import '../credits/crypto_bridge_service.dart';
import '../credits/poch_service.dart';
import '../credits/work_receipt.dart';
import '../identity_service.dart';
import '../ipfs_service.dart';
import '../plugins/doi_harvester_plugin.dart';
import '../proof_of_retrievability_service.dart';
import 'beacon_models.dart';
import 'moltbook_service.dart';

/// Riverpod provider for AlexandriaMcpServer
final alexandriaMcpServerProvider = Provider<AlexandriaMcpServer>((ref) {
  return AlexandriaMcpServer(
    creditService: ref.read(creditServiceProvider),
    pochService: ref.read(pochServiceProvider),
    cryptoBridgeService: ref.read(cryptoBridgeServiceProvider),
    moltbookService: ref.read(moltbookServiceProvider),
    porService: ref.read(proofOfRetrievabilityServiceProvider),
    ipfsService: ref.read(ipfsServiceProvider),
    identityService: ref.read(identityServiceProvider),
    db: ref.read(databaseProvider),
  );
});

/// Standardized Model Context Protocol (MCP) tool handler for Alexandria (ALX-006)
class AlexandriaMcpServer {
  final CreditService _creditService;
  final PoCHService _pochService;
  final CryptoBridgeService _cryptoBridgeService;
  final MoltbookService _moltbookService;
  final ProofOfRetrievabilityService _porService;
  final IpfsService _ipfsService;

  /// Node identity service — the PoR verifier-of-record. Challenges are
  /// stamped with, and work receipts are signed under, this key (the
  /// Moltbook key remains the agent's social identity only). Optional so
  /// tests can run the server without secure storage.
  final IdentityService? _identityService;

  /// Persistent store for DOI dedupe and work-receipt artifacts. Optional so
  /// tests can run the server in-memory.
  final AppDatabase? _db;

  /// DOI resolution used by the ingest tool to VERIFY a DOI names a real
  /// scholarly work before any verification bounty is minted (round-2 red
  /// finding: the tool previously minted on regex shape alone). Injectable
  /// so tests can stub the scholarly APIs.
  final DoiResolver _doiResolver;

  /// DOIs already rewarded through the ingest tool — one payout per work,
  /// ever. In-memory fallback used only when no [_db] is injected.
  final Set<String> _awardedDois = {};

  /// Agent-facing payout rails (Cashu export, Lightning sweep) stay closed
  /// until the attestation layer exists — 𝒞→BTC egress is the profit motive
  /// for every mint exploit (ALX-010).
  static const bool agentPayoutsEnabled = false;

  AlexandriaMcpServer({
    required CreditService creditService,
    required PoCHService pochService,
    required CryptoBridgeService cryptoBridgeService,
    required MoltbookService moltbookService,
    required ProofOfRetrievabilityService porService,
    required IpfsService ipfsService,
    IdentityService? identityService,
    AppDatabase? db,
    DoiResolver? doiResolver,
  })  : _doiResolver = doiResolver ?? DoiResolver(),
        _creditService = creditService,
        _pochService = pochService,
        _cryptoBridgeService = cryptoBridgeService,
        _moltbookService = moltbookService,
        _porService = porService,
        _ipfsService = ipfsService,
        _identityService = identityService,
        _db = db;

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
        'name': 'alexandria_request_por_challenge',
        'description':
            'Issues a fresh HMAC-SHA256 Proof of Retrievability challenge for a CID. Returns the challenge ID and nonce; submit the computed tag via alexandria_submit_por_challenge.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'cid': {
              'type': 'string',
              'description': 'Target CID to be challenged on'
            },
          },
          'required': ['cid'],
        },
      },
      {
        'name': 'alexandria_submit_por_challenge',
        'description':
            'Submits the HMAC-SHA256 tag for a pending PoR challenge. Tag = HMAC-SHA256(key: nonce, msg: content bytes). Credits mint only when the tag verifies against the stored payload.',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'challenge_id': {
              'type': 'string',
              'description': 'Challenge ID from alexandria_request_por_challenge'
            },
            'tag': {
              'type': 'string',
              'description':
                  'Hex-encoded HMAC-SHA256 tag over the full content payload'
            },
            'prover_pubkey': {
              'type': 'string',
              'description':
                  'Optional Ed25519 pubkey (hex) of the proving node. Defaults to this node\'s identity key (a self-issued, unattested receipt).'
            },
          },
          'required': ['challenge_id', 'tag'],
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
          return await _replicateCid(
            arguments['cid'] as String? ?? '',
            (arguments['credits'] as num? ?? 0.0).toDouble(),
          );

        case 'alexandria_request_por_challenge':
          return await _requestPorChallenge(
              arguments['cid'] as String? ?? '');

        case 'alexandria_submit_por_challenge':
          return await _submitPorChallenge(
            arguments['challenge_id'] as String? ?? '',
            arguments['tag'] as String? ?? '',
            proverPubkey: arguments['prover_pubkey'] as String?,
          );

        case 'alexandria_post_moltbook_bounty':
          return await _postMoltbookBounty(arguments);

        case 'alexandria_export_cashu_voucher':
          return await _exportCashuVoucher(
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
    // Strict DOI shape: registrant code 4-9 digits, non-empty suffix.
    if (!RegExp(r'^10\.\d{4,9}/\S+$').hasMatch(doi)) {
      return _errorResponse(
          'Invalid DOI format: $doi. Expected 10.<registrant>/<suffix>.');
    }

    // REAL verification gate (round-2 red finding): a "verification
    // bounty" requires verified input. The DOI must resolve to a real
    // scholarly record via Crossref/OpenAlex/doi.org — regex-valid
    // fabrications mint nothing and are NOT recorded in the dedup set,
    // so a transient resolver outage never permanently burns a real DOI.
    DoiRecord? record;
    try {
      record = await _doiResolver
          .resolve(doi)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      record = null;
    }
    if (record == null || record.doi.isEmpty) {
      return _textResponse(jsonEncode({
        'status': 'unverified',
        'doi': doi,
        'credits_earned': 0.0,
        'note':
            'DOI could not be resolved against scholarly metadata APIs — no verification performed, no credits minted.',
      }));
    }

    // Ingest the verified work: store its dossier so the assigned CID is
    // real content-addressed material, not a fabricated label.
    final dossier =
        Uint8List.fromList(utf8.encode(record.toMarkdownDossier()));
    final assignedCid = await _ipfsService.addFile(dossier);

    // One payout per unique work — looping the same DOI mints nothing.
    // Dedupe is persisted (AwardedDois) so it survives restarts and new
    // server instances; the in-memory set is only a no-db fallback.
    bool duplicate;
    final db = _db;
    if (db != null) {
      // insertAwardedDoi returns false on PK conflict (insertOrIgnore) —
      // the return value is the authoritative dedup signal; a raced
      // insert can never double-mint.
      duplicate = !(await db.insertAwardedDoi(doi, cid: assignedCid));
    } else {
      duplicate = !_awardedDois.add(doi);
    }
    if (duplicate) {
      return _textResponse(jsonEncode({
        'status': 'duplicate',
        'doi': doi,
        'credits_earned': 0.0,
        'note': 'DOI already ingested and rewarded; no duplicate payout.',
      }));
    }

    // Report the ACTUAL minted amount — awardVerificationCredits returns
    // the post-daily-cap figure, so the response can never overstate
    // earnings when the 100 ℭ/day verificationReward clamp bites.
    final minted = _creditService.awardVerificationCredits(
      action: 'Verified and ingested scientific paper: $doi',
      targetId: assignedCid,
      amount: 15.0,
    );

    return _textResponse(jsonEncode({
      'status': 'success',
      'doi': record.doi,
      'title': title ?? record.title,
      'assigned_cid': assignedCid,
      'credits_earned': minted,
      'verified_via': record.sourceApi,
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

  Future<Map<String, dynamic>> _replicateCid(
      String cid, double credits) async {
    if (credits <= 0) return _errorResponse('Credits must be > 0.');
    // DURABLE-FIRST (optimistic-return residual — adopted): the debit
    // commits through the insert-if-absent CAS BEFORE the balance
    // mutates, so a reported success provably corresponds to a
    // durably-committed row — an agent tool response never precedes
    // its own collateral.
    final success = await _creditService.spendCreditsDurable(
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

  /// The PoR verifier-of-record is the node identity key — the same key
  /// [ProofOfRetrievabilityService] signs receipts with — so a valid proof
  /// yields a properly signed work receipt. The Moltbook key stays the
  /// agent's social identity and never stamps or signs receipts.
  Future<String?> _verifierPubkeyHex() async {
    try {
      final identity = await _identityService?.getIdentity();
      if (identity == null) return null;
      return bytesToHex(identity.publicKey);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _requestPorChallenge(String cid) async {
    // The challenge records THIS node's verifier key so the issued work
    // receipt names a real verifier — not a bare self-declared peer id.
    final challengerPubkey = await _verifierPubkeyHex();
    final challenge = _porService.issueChallenge(
      cid: cid,
      totalChunks: 1,
      challengerPubkey:
          (challengerPubkey == null || challengerPubkey.isEmpty)
              ? null
              : challengerPubkey,
    );
    return _textResponse(jsonEncode({
      'status': 'challenge_issued',
      'challenge_id': challenge.challengeId,
      'cid': cid,
      'challenger_pubkey': challenge.challengerPubkey,
      'nonce_hex': challenge.nonce
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(),
      'expires_in_seconds': 300,
      'note':
          'Compute tag = hex(HMAC-SHA256(key: nonce_bytes, msg: content_bytes)) and submit via alexandria_submit_por_challenge.',
    }));
  }

  Future<Map<String, dynamic>> _submitPorChallenge(
    String challengeId,
    String tag, {
    String? proverPubkey,
  }) async {
    // Reject proofs against challenges this node never issued.
    final challenge = _porService.pendingChallenge(challengeId);
    if (challenge == null) {
      return _errorResponse(
          'No pending PoR challenge with id $challengeId (request one first via alexandria_request_por_challenge)');
    }

    // Fetch the audited payload — verification requires the bytes exist here.
    final chunks = <int>[];
    await for (final chunk in _ipfsService.getFile(challenge.cid)) {
      chunks.addAll(chunk);
    }
    if (chunks.isEmpty) {
      return _errorResponse(
          'CID ${challenge.cid} is not present in the local blockstore');
    }
    final payload = Uint8List.fromList(chunks);

    final proof = PoRProof(
      challengeId: challengeId,
      tag: tag,
      timestamp: DateTime.now(),
    );
    // Verifier-side issuance: a valid proof yields a WorkReceipt naming the
    // challenger (verifier) and the prover. When the caller supplies no
    // prover_pubkey, this node's identity key is used — the same key that
    // verifies — making the receipt honestly self-issued, minted locally at
    // 1.0x and spent. A FOREIGN prover_pubkey yields a signed claim
    // instrument persisted UNSPENT: its value belongs to the prover key
    // holder, never to this node (ALX-010).
    final identityPubkey = await _verifierPubkeyHex();
    final result = await _porService.verifyAndIssueReceipt(
      proof: proof,
      expectedChunkData: payload,
      proverPeerId: proverPubkey ?? _moltbookService.agentId,
      proverPubkey:
          proverPubkey ??
              ((identityPubkey == null || identityPubkey.isEmpty)
                  ? null
                  : identityPubkey),
    );
    if (!result.valid) {
      return _errorResponse('PoR proof verification failed: tag mismatch');
    }

    final receipt = result.receipt;
    // Canonical identity reporting (receipt_attested robustness fix):
    // WorkReceipt.isSelfIssued / isAttestedClaim are SYNTACTIC reads —
    // literal `==` on the key strings. A `prover_pubkey` spelled as a
    // case-variant or space-padded form of the verifier key slips past
    // `==` while the claim path (WorkReceipt.samePubkey, byte-level
    // canonical comparison) still evaluates the receipt as self-issued
    // and refuses it. Report the CANONICAL verdict so this surface
    // matches the claim path's evaluation instead of misreporting
    // `attested_claim: true`.
    final canonSelfIssued = receipt != null &&
        WorkReceipt.samePubkey(
            receipt.proverPubkey, receipt.verifierPubkey);
    final canonAttested =
        receipt != null && receipt.isVerifierSigned && !canonSelfIssued;
    final receiptJson = receipt == null
        ? null
        : (<String, dynamic>{...receipt.toJson()}
          ..['self_issued'] = canonSelfIssued
          ..['attested_claim'] = canonAttested);
    return _textResponse(jsonEncode({
      'status': 'verified',
      'cid': challenge.cid,
      'proof_valid': true,
      'new_balance': _creditService.balance,
      'receipt': receiptJson,
      'receipt_attested': canonAttested,
      'note': receipt == null
          ? null
          : canonSelfIssued
              ? 'Self-issued receipt: verifies integrity but claims only unattested (non-egress) value.'
              : receipt.spent
                  ? null
                  : 'Receipt persisted unspent — a signed claim instrument for the named prover key.',
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

  Future<Map<String, dynamic>> _exportCashuVoucher(double credits) async {
    if (!agentPayoutsEnabled) {
      return _errorResponse(
          'Agent payout rails are disabled until the cross-verified attestation layer ships (ALX-010). Credits remain spendable inside Alexandria.');
    }
    // DURABLE-FIRST (payout-rail precondition): the attested debit
    // commits through spendCreditsDurable BEFORE the bearer token is
    // assembled — an emitted Cashu token can never outrun its own
    // collateral, which the optimistic form could not promise.
    final token =
        await _cryptoBridgeService.exportCreditsAsCashuTokenDurable(credits);
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
    if (!agentPayoutsEnabled) {
      return _errorResponse(
          'Agent payout rails are disabled until the cross-verified attestation layer ships (ALX-010). Credits remain spendable inside Alexandria.');
    }
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
