import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart'
    show AppDatabase, databaseProvider;
import 'package:alexandria/services/agent/alexandria_mcp_server.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/plugins/doi_harvester_plugin.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';

/// Identity stub whose Ed25519 keypair the test controls - the PoR
/// verifier-of-record the MCP server stamps challenges with and the
/// service signs receipts under.
class _FakeIdentityService implements IdentityService {
  _FakeIdentityService(this.keyPair, this.publicKeyBytes);

  final SimpleKeyPair keyPair;
  final Uint8List publicKeyBytes;

  String get pubkeyHex => bytesToHex(publicKeyBytes);

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

/// Deterministic resolver stub: DOI ingest now requires a VERIFIED
/// scholarly record before minting (round-2 fix - fabricated DOIs mint
/// nothing), so tests inject a resolver instead of hitting Crossref.
class _StubDoiResolver extends DoiResolver {
  @override
  Future<DoiRecord?> resolve(String rawDoi) async {
    final doi = DoiResolver.normalizeDoi(rawDoi);
    if (doi.isEmpty) return null;
    return DoiRecord(
      doi: doi,
      title: 'Stubbed scholarly record for $doi',
      authors: const ['Test Author'],
      journal: 'Journal of Test Doubles',
      sourceApi: 'stub',
    );
  }
}

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
    late AppDatabase db;
    late _FakeIdentityService identity;

    setUp(() async {
      final keyPair = await Ed25519().newKeyPair();
      final pub = await keyPair.extractPublicKey();
      identity = _FakeIdentityService(keyPair, Uint8List.fromList(pub.bytes));

      pochService = PoCHService();
      db = AppDatabase();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
      // verifyProof mints through the container's creditServiceProvider -
      // override it so the award lands on the instance under test. The PoR
      // service reads identityServiceProvider for its verifier key.
      container = ProviderContainer(overrides: [
        creditServiceProvider.overrideWith((_) => creditService),
        databaseProvider.overrideWithValue(db),
        identityServiceProvider.overrideWithValue(identity),
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
        identityService: identity,
        db: db,
        doiResolver: _StubDoiResolver(),
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
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
      // An empty archive must report zero matches - no fabricated
      // index entries may pad the response.
      final empty = await mcpServer
          .callTool('alexandria_search_archive', {'query': 'Physics'});
      expect(empty['isError'], isFalse);
      final emptyData =
          jsonDecode((empty['content'] as List).first['text'] as String);
      expect(emptyData['query'], 'Physics');
      expect(emptyData['total_matches'], 0);

      // A real held manifest is findable by title.
      await db.insertManifest({
        'uuid': 'test-uuid-1',
        'title': 'Quantum Physics Preprint',
        'lastUpdated': DateTime.now(),
        'tags': 'physics,quantum',
      });
      final manifest = await db.getManifestByUuid('test-uuid-1');
      await db.insertVersion({
        'manifestId': manifest!['id'] as int,
        'cid': 'bafkrealheldcid',
        'sizeBytes': 512,
      });

      final res = await mcpServer
          .callTool('alexandria_search_archive', {'query': 'Physics'});
      expect(res['isError'], isFalse);
      final data = jsonDecode((res['content'] as List).first['text'] as String);
      expect(data['total_matches'], 1);
      final match = (data['matches'] as List).first as Map<String, dynamic>;
      expect(match['cid'], 'bafkrealheldcid');
      expect(match['title'], 'Quantum Physics Preprint');
      expect(match['replicas'], isA<int>());
      expect(match['pinned'], isA<bool>());

      // Non-matching queries stay empty.
      final miss = await mcpServer
          .callTool('alexandria_search_archive', {'query': 'Botany'});
      final missData =
          jsonDecode((miss['content'] as List).first['text'] as String);
      expect(missData['total_matches'], 0);
    });

    test('executes alexandria_ingest_doi tool and awards verification credits',
        () async {
      final initialBalance = creditService.balance;

      final res = await mcpServer.callTool('alexandria_ingest_doi', {
        'doi': '10.1038/nature12373',
        'title': 'Quantum teleportation between distant matter qubits',
      });

      expect(res['isError'], isFalse);
      final text = (res['content'] as List).first['text'] as String;
      final data = jsonDecode(text) as Map<String, dynamic>;
      expect(data['status'], 'success');
      // The assigned CID is now REAL content-addressed material (the
      // resolved dossier bytes), not a fabricated label containing the
      // DOI string - verify it parses as a structurally valid CID.
      expect(data['assigned_cid'], isNotEmpty);
      expect(CidService().isValidCid(data['assigned_cid'] as String), isTrue);
      expect(data['verified_via'], 'stub');
      expect(creditService.balance, initialBalance + 15.0);

      // Re-ingesting the same DOI pays nothing (ALX-010 dedupe)
      final dupeRes = await mcpServer.callTool('alexandria_ingest_doi', {
        'doi': '10.1038/nature12373',
      });
      expect(dupeRes['isError'], isFalse);
      final dupeData =
          jsonDecode((dupeRes['content'] as List).first['text'] as String)
              as Map<String, dynamic>;
      expect(dupeData['status'], 'duplicate');
      expect(dupeData['credits_earned'], 0.0);
      expect(creditService.balance, initialBalance + 15.0);

      // Rejects invalid DOI prefix
      final invalidRes = await mcpServer
          .callTool('alexandria_ingest_doi', {'doi': 'invalid_doi_format'});
      expect(invalidRes['isError'], isTrue);
    });

    test('DOI dedupe persists across a new server instance on the same db',
        () async {
      // A fresh AlexandriaMcpServer has an empty in-memory dedupe set; only
      // the persisted AwardedDois table can catch the re-ingest.
      final secondServer = AlexandriaMcpServer(
        creditService: creditService,
        pochService: pochService,
        cryptoBridgeService: cryptoBridgeService,
        moltbookService: moltbookService,
        porService: porService,
        ipfsService: ipfsService,
        db: db,
        doiResolver: _StubDoiResolver(),
      );

      final first = await mcpServer.callTool('alexandria_ingest_doi', {
        'doi': '10.1126/science.persisted-dedupe',
      });
      expect(first['isError'], isFalse);
      expect(
          jsonDecode(
              (first['content'] as List).first['text'] as String)['status'],
          'success');
      expect(
          await db.hasAwardedDoi('10.1126/science.persisted-dedupe'), isTrue);

      final second = await secondServer.callTool('alexandria_ingest_doi', {
        'doi': '10.1126/science.persisted-dedupe',
      });
      expect(second['isError'], isFalse);
      final data =
          jsonDecode((second['content'] as List).first['text'] as String)
              as Map<String, dynamic>;
      expect(data['status'], 'duplicate');
      expect(data['credits_earned'], 0.0);
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

    test('executes alexandria_replicate_cid tool with credit deduction',
        () async {
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
      final challengeData =
          jsonDecode((challengeRes['content'] as List).first['text'] as String)
              as Map<String, dynamic>;
      final challengeId = challengeData['challenge_id'] as String;
      final nonceHex = challengeData['nonce_hex'] as String;
      // The verifier-of-record is the node identity key - the same key the
      // PoR service signs receipts under (no more ephemeral moltbook key).
      expect(challengeData['challenger_pubkey'], identity.pubkeyHex);

      // 2. Compute the tag the prover would produce
      final nonceBytes = Uint8List.fromList(List.generate(nonceHex.length ~/ 2,
          (i) => int.parse(nonceHex.substring(i * 2, i * 2 + 2), radix: 16)));
      final tag = Hmac(sha256, nonceBytes).convert(payload).toString();

      // 3. Submit - verifies, issues a verifier-signed work receipt
      final res = await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': challengeId,
        'tag': tag,
      });
      expect(res['isError'], isFalse);
      expect(creditService.balance, greaterThan(initialBalance));

      final submitData =
          jsonDecode((res['content'] as List).first['text'] as String)
              as Map<String, dynamic>;
      expect(submitData['status'], 'verified');
      final receipt = submitData['receipt'] as Map<String, dynamic>?;
      expect(receipt, isNotNull);
      expect(receipt!['receipt_id'], isNotEmpty);
      // Signed under the IdentityService key - the request→submit
      // round-trip produces a real verifier-signed receipt.
      expect(receipt['verifier_pubkey'], identity.pubkeyHex);
      expect(receipt['verifier_sig'], isNotEmpty);
      expect(receipt['prover_pubkey'], identity.pubkeyHex);
      // The MCP harness is challenger AND prover on one node - the receipt
      // is self-issued, so it must never claim attested (egress) value.
      expect(submitData['receipt_attested'], isFalse);
      expect(receipt['self_issued'], isTrue);
      // Local prover → the receipt was consumed by the local claim, and the
      // reported spent flag matches the persisted row.
      expect(receipt['spent'], isTrue);
      final row = await db.getWorkReceipt(receipt['receipt_id'] as String);
      expect(row!['spent'], isTrue);

      // 4. A wrong tag is rejected - no payout
      final challenge2 = await mcpServer
          .callTool('alexandria_request_por_challenge', {'cid': cid});
      final id2 =
          jsonDecode((challenge2['content'] as List).first['text'] as String)[
              'challenge_id'] as String;
      final failRes =
          await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': id2,
        'tag': 'deadbeef' * 8,
      });
      expect(failRes['isError'], isTrue);

      // 5. A fabricated challenge ID is rejected outright
      final forgedRes =
          await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': 'forged_id_12345',
        'tag': tag,
      });
      expect(forgedRes['isError'], isTrue);
    });

    test(
        'PoR submit for a foreign prover persists an unspent signed '
        'claim instrument — no local mint', () async {
      final payload = Uint8List.fromList(
          utf8.encode('payload proven for a remote prover agent'));
      final cid = await ipfsService.addFile(payload);
      final initialBalance = creditService.balance;

      final challengeRes = await mcpServer
          .callTool('alexandria_request_por_challenge', {'cid': cid});
      final challengeData =
          jsonDecode((challengeRes['content'] as List).first['text'] as String)
              as Map<String, dynamic>;
      final challengeId = challengeData['challenge_id'] as String;
      final nonceHex = challengeData['nonce_hex'] as String;
      final nonceBytes = Uint8List.fromList(List.generate(nonceHex.length ~/ 2,
          (i) => int.parse(nonceHex.substring(i * 2, i * 2 + 2), radix: 16)));
      final tag = Hmac(sha256, nonceBytes).convert(payload).toString();

      final foreignProver = 'aa'.padRight(64, 'b'); // foreign Ed25519 hex
      final res = await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': challengeId,
        'tag': tag,
        'prover_pubkey': foreignProver,
      });
      expect(res['isError'], isFalse);

      final data = jsonDecode((res['content'] as List).first['text'] as String)
          as Map<String, dynamic>;
      expect(data['status'], 'verified');
      final receipt = data['receipt'] as Map<String, dynamic>;
      expect(receipt['verifier_pubkey'], identity.pubkeyHex);
      expect(receipt['verifier_sig'], isNotEmpty);
      expect(receipt['prover_pubkey'], foreignProver);
      expect(receipt['self_issued'], isFalse);
      // The artifact IS an attested claim - for the prover. This node
      // neither mints it nor burns it: persisted unspent, balance flat.
      expect(data['receipt_attested'], isTrue);
      expect(receipt['spent'], isFalse);
      expect(creditService.balance, equals(initialBalance));

      final row = await db.getWorkReceipt(receipt['receipt_id'] as String);
      expect(row!['spent'], isFalse);
    });

    test(
        'case-variant prover_pubkey reports the CANONICAL self-issued '
        'verdict — receipt_attested never misreports', () async {
      // Regression for the WORKING_ON residual: `isSelfIssued` composed a
      // literal `==`, so a prover_pubkey spelled as the case-variant of
      // the verifier key reported attested_claim:true while the claim
      // path (WorkReceipt.samePubkey) evaluated it as self-issued and
      // minted at local 1.0x. The report must now match the claim path.
      final payload = Uint8List.fromList(
          utf8.encode('payload proven under a case-variant key spelling'));
      final cid = await ipfsService.addFile(payload);
      final initialBalance = creditService.balance;

      final challengeRes = await mcpServer
          .callTool('alexandria_request_por_challenge', {'cid': cid});
      final challengeData =
          jsonDecode((challengeRes['content'] as List).first['text'] as String)
              as Map<String, dynamic>;
      final challengeId = challengeData['challenge_id'] as String;
      final nonceHex = challengeData['nonce_hex'] as String;
      final nonceBytes = Uint8List.fromList(List.generate(nonceHex.length ~/ 2,
          (i) => int.parse(nonceHex.substring(i * 2, i * 2 + 2), radix: 16)));
      final tag = Hmac(sha256, nonceBytes).convert(payload).toString();

      // UPPERCASE spelling of the identity key: byte-identical key
      // material, literal `==` differs.
      final caseVariant = identity.pubkeyHex.toUpperCase();
      expect(caseVariant == identity.pubkeyHex, isFalse);
      final res = await mcpServer.callTool('alexandria_submit_por_challenge', {
        'challenge_id': challengeId,
        'tag': tag,
        'prover_pubkey': caseVariant,
      });
      expect(res['isError'], isFalse);
      final data = jsonDecode((res['content'] as List).first['text'] as String)
          as Map<String, dynamic>;
      final receipt = data['receipt'] as Map<String, dynamic>;
      expect(receipt['prover_pubkey'], caseVariant);
      // The reported verdict is the canonical one: self-issued, NOT
      // attested - matching what claimVerifiedReceipt would evaluate.
      expect(data['receipt_attested'], isFalse);
      expect(receipt['self_issued'], isTrue);
      expect(receipt['attested_claim'], isFalse);
      expect(data['note'], contains('Self-issued'));
      // And it really was treated as a local (self) claim: minted at
      // 1.0x and spent, exactly as the claim path evaluates it.
      expect(receipt['spent'], isTrue);
      expect(creditService.balance, greaterThan(initialBalance));
    });

    test('agent payout rails are disabled until attestation (ALX-010)',
        () async {
      final res = await mcpServer.callTool('alexandria_export_cashu_voucher', {
        'credits': 10.0,
      });
      expect(res['isError'], isTrue);

      final sweepRes =
          await mcpServer.callTool('alexandria_sweep_lightning_live', {
        'lightning_address': 'agent@walletofsatoshi.com',
        'credits': 10.0,
      });
      expect(sweepRes['isError'], isTrue);
    });

    test('handles JSON-RPC 2.0 dispatch for tools/list and tools/call',
        () async {
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

    test('executes alexandria_sweep_lightning_live tool with validation',
        () async {
      // Disabled rail rejects before address validation (ALX-010)
      final errRes =
          await mcpServer.callTool('alexandria_sweep_lightning_live', {
        'lightning_address': 'not_an_email',
        'credits': 10.0,
      });
      expect(errRes['isError'], isTrue);
    });
  });
}
