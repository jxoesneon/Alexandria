import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' hide Hmac;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/app_network.dart';
import 'package:alexandria/data/database.dart'
    show AppDatabase, databaseProvider, dbFileName;
import 'package:alexandria/services/agent/alexandria_mcp_server.dart';
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/credits/poch_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';
import 'package:alexandria/services/plugins/doi_harvester_plugin.dart';
import 'package:alexandria/services/proof_of_retrievability_service.dart';
import 'package:alexandria/services/rendezvous_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

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

class _StubDoiResolver extends DoiResolver {
  @override
  Future<DoiRecord?> resolve(String rawDoi) async {
    final doi = DoiResolver.normalizeDoi(rawDoi);
    if (doi.isEmpty) return null;
    return DoiRecord(
      doi: doi,
      title: 'Testnet scholarly record for $doi',
      authors: const ['Testnet Author'],
      journal: 'Journal of Testnet Doubles',
      sourceApi: 'stub',
    );
  }
}

Map<String, dynamic> _payload(Map<String, dynamic> res) =>
    jsonDecode((res['content'] as List).first['text'] as String)
        as Map<String, dynamic>;

void main() {
  group('AlexandriaMcpServer on the isolated test network', () {
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

    Future<Map<String, dynamic>> rpc(
            String method, Map<String, dynamic> params) =>
        mcpServer.handleJsonRpcRequest(
            {'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params});

    setUp(() async {
      AppNetwork.testnet = true;

      final keyPair = await Ed25519().newKeyPair();
      final pub = await keyPair.extractPublicKey();
      identity = _FakeIdentityService(keyPair, Uint8List.fromList(pub.bytes));

      pochService = PoCHService();
      db = AppDatabase();
      creditService = CreditService(
        pochService: pochService,
        initialBalance: 100.0,
      );
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
      AppNetwork.testnet = false;
      container.dispose();
      await db.close();
    });

    test('every network surface is scoped while tools run', () {
      expect(SecureStorageService().keyPrefix, 'testnet_');
      expect(dbFileName, 'alexandria_testnet.sqlite');
      expect(RendezvousService.topic, '/alexandria-testnet/rendezvous/1');
      expect(RendezvousService.signDomain, 'ALX-TESTNET-RENDEZVOUS/1');
      expect(MeshTransportService.handshakeProtocol, 'ALX-TESTNET-MESH/1');
      expect(AppNetwork.privateNetworkPsk, isNotNull);
    });

    test('tools/list serves all 9 tools over JSON-RPC', () async {
      final res = await rpc('tools/list', {});
      final tools = (res['result'] as Map)['tools'] as List;
      expect(tools.length, 9);
    });

    test('full testnet journey: ingest, search, replicate, PoR, bounty',
        () async {
      // 1. Wallet: sandbox balance is readable.
      final bal = await rpc('tools/call', {
        'name': 'alexandria_get_wallet_balance',
        'arguments': <String, dynamic>{},
      });
      final balData = _payload(bal['result'] as Map<String, dynamic>);
      expect(balData['balance_credits'], 100.0);

      // 2. DOI ingest: resolves, stores real content, mints sandbox
      // credits - the dedupe ledger lives in the testnet DB.
      final ingest = await rpc('tools/call', {
        'name': 'alexandria_ingest_doi',
        'arguments': {'doi': '10.5555/testnet.1234'},
      });
      final ingestData = _payload(ingest['result'] as Map<String, dynamic>);
      expect(ingestData['status'], 'success');
      final cid = ingestData['assigned_cid'] as String;
      expect(cid, isNotEmpty);
      expect(ingestData['credits_earned'], greaterThan(0));

      // Re-ingest is deduped - no double mint.
      final dup = await rpc('tools/call', {
        'name': 'alexandria_ingest_doi',
        'arguments': {'doi': '10.5555/testnet.1234'},
      });
      expect(_payload(dup['result'] as Map<String, dynamic>)['status'],
          'duplicate');

      // 3. Search: the real archive answers - no fabricated records.
      await db.insertManifest({
        'uuid': 'testnet-manifest-1',
        'title': 'Testnet Quantum Preprint',
        'lastUpdated': DateTime.now(),
        'metadata': jsonEncode({'doi': '10.5555/testnet.1234'}),
      });
      final manifest = await db.getManifestByUuid('testnet-manifest-1');
      await db.insertVersion({
        'manifestId': manifest!['id'] as int,
        'cid': 'bafktestnetheld',
        'sizeBytes': 256,
      });
      final search = await rpc('tools/call', {
        'name': 'alexandria_search_archive',
        'arguments': {'query': 'Quantum'},
      });
      final searchData = _payload(search['result'] as Map<String, dynamic>);
      expect(searchData['total_matches'], 1);
      expect((searchData['matches'] as List).first['cid'], 'bafktestnetheld');
      expect(
          (searchData['matches'] as List).first['doi'], '10.5555/testnet.1234');

      // 4. Replicate: the debit is real; the response claims no fake
      // dispatch work.
      final rep = await rpc('tools/call', {
        'name': 'alexandria_replicate_cid',
        'arguments': {'cid': 'bafktestnetheld', 'credits': 5.0},
      });
      final repData = _payload(rep['result'] as Map<String, dynamic>);
      expect(repData['status'], 'success');
      expect(repData['swarm_tasks_dispatched'], 0);
      expect(creditService.balance, lessThan(115.0));

      // 5. PoR round-trip on the locally held payload.
      final payload = Uint8List.fromList(utf8.encode('testnet por payload'));
      final porCid = await ipfsService.addFile(payload);
      final challenge = await rpc('tools/call', {
        'name': 'alexandria_request_por_challenge',
        'arguments': {'cid': porCid},
      });
      final chData = _payload(challenge['result'] as Map<String, dynamic>);
      expect(chData['status'], 'challenge_issued');
      final nonceHex = chData['nonce_hex'] as String;
      final nonceBytes = Uint8List.fromList(List.generate(nonceHex.length ~/ 2,
          (i) => int.parse(nonceHex.substring(i * 2, i * 2 + 2), radix: 16)));
      final tag = Hmac(sha256, nonceBytes).convert(payload).toString();
      final submit = await rpc('tools/call', {
        'name': 'alexandria_submit_por_challenge',
        'arguments': {'challenge_id': chData['challenge_id'], 'tag': tag},
      });
      final subData = _payload(submit['result'] as Map<String, dynamic>);
      expect(subData['proof_valid'], isTrue);

      // 6. Moltbook bounty: lands on the TESTNET submolt only - the
      // response, the feed record, and the signed wire payload all
      // carry the scoped channel.
      final bounty = await rpc('tools/call', {
        'name': 'alexandria_post_moltbook_bounty',
        'arguments': {
          'cid': 'bafktestnetheld',
          'title': 'Testnet preservation bounty',
          'credits_reward': 10.0,
        },
      });
      final bountyData = _payload(bounty['result'] as Map<String, dynamic>);
      expect(bountyData['status'], 'published');
      expect(bountyData['moltbook_submolt'], 'alexandria-bounties-testnet');

      final feed = moltbookService.getPostsForSubmolt('alexandria-bounties');
      expect(feed, hasLength(1));
      expect(feed.first.submolt, 'alexandria-bounties-testnet');
      expect(feed.first.beaconEnvelope!.payload['submolt'],
          'alexandria-bounties-testnet');

      // The bounty is findable through archive search by title and
      // DOI - active bounties merge into the real result set.
      final bSearch = await rpc('tools/call', {
        'name': 'alexandria_search_archive',
        'arguments': {'query': 'preservation bounty'},
      });
      final bData = _payload(bSearch['result'] as Map<String, dynamic>);
      expect(bData['total_matches'], 1);
      final bMatch = (bData['matches'] as List).first;
      expect(bMatch['cid'], 'bafktestnetheld');
      expect(bMatch['bounty_credits'], 10.0);

      // A bounty carrying a DOI matches on the DOI itself.
      await rpc('tools/call', {
        'name': 'alexandria_post_moltbook_bounty',
        'arguments': {
          'cid': 'bafkdoitagged',
          'doi': '10.5555/testnet.bounty',
          'title': 'DOI-tagged bounty',
          'credits_reward': 3.0,
        },
      });
      final doiSearch = await rpc('tools/call', {
        'name': 'alexandria_search_archive',
        'arguments': {'query': 'testnet.bounty'},
      });
      final doiData = _payload(doiSearch['result'] as Map<String, dynamic>);
      expect(doiData['total_matches'], 1);
      expect((doiData['matches'] as List).first['cid'], 'bafkdoitagged');

      // 7. Payout rails refuse under testnet: sandbox credits never
      // attempt real egress.
      final voucher = await rpc('tools/call', {
        'name': 'alexandria_export_cashu_voucher',
        'arguments': {'credits': 5.0},
      });
      expect(voucher['result']['isError'], isTrue);

      final sweep = await rpc('tools/call', {
        'name': 'alexandria_sweep_lightning_live',
        'arguments': {
          'lightning_address': 'user@walletofsatoshi.com',
          'credits': 5.0,
        },
      });
      expect(sweep['result']['isError'], isTrue);

      // 8. Cross-network contamination check: nothing written can be
      // read back through the mainnet names.
      AppNetwork.testnet = false;
      try {
        expect(
            moltbookService.getPostsForSubmolt('alexandria-bounties'), isEmpty);
      } finally {
        AppNetwork.testnet = true;
      }
    });
  });
}
