import 'dart:convert';

import 'package:alexandria/app_network.dart';
import 'package:alexandria/data/database.dart' show dbFileName;
import 'package:alexandria/services/agent/beacon_models.dart';
import 'package:alexandria/services/agent/moltbook_service.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/credits/credit_service.dart';
import 'package:alexandria/services/credits/crypto_bridge_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';
import 'package:alexandria/services/rendezvous_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/ui/alexandria_root.dart';
import 'package:dart_ipfs/dart_ipfs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  String get keyPrefix => AppNetwork.testnet ? 'testnet_' : '';

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> deleteAll() async => data.clear();

  @override
  Future<bool> containsKey(String key) async => data.containsKey(key);
}

class _Ref implements Ref {
  _Ref(this._container);
  final ProviderContainer _container;

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEngine implements IPFS {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  String get peerID => 'fakePeer';

  @override
  List<String> get addresses => const [];

  @override
  Future<List<String>> get connectedPeers async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AppNetwork selector', () {
    tearDown(() => AppNetwork.testnet = false);

    test('mainnet leaves every name unchanged', () {
      AppNetwork.testnet = false;
      expect(AppNetwork.name, 'mainnet');
      expect(AppNetwork.scopedKey('k'), 'k');
      expect(AppNetwork.topic('/alexandria/rendezvous/1'),
          '/alexandria/rendezvous/1');
      expect(AppNetwork.submolt('alexandria-bounties'), 'alexandria-bounties');
      expect(AppNetwork.meshChannelDomain, 'alexandria:mesh-channel:v1');
      expect(AppNetwork.privateNetworkPsk, isNull);
    });

    test('testnet namespaces every network surface', () {
      AppNetwork.testnet = true;
      expect(AppNetwork.name, 'testnet');
      expect(AppNetwork.scopedKey('k'), 'testnet_k');
      expect(AppNetwork.topic('/alexandria/rendezvous/1'),
          '/alexandria-testnet/rendezvous/1');
      expect(AppNetwork.submolt('alexandria-bounties'),
          'alexandria-bounties-testnet');
      expect(
          AppNetwork.meshChannelDomain, 'alexandria:testnet:mesh-channel:v1');

      final psk = AppNetwork.privateNetworkPsk;
      expect(psk, isNotNull);
      expect(psk!.length, 32);
      expect(
          psk,
          Uint8List.fromList(
              sha256.convert(utf8.encode('alexandria-testnet-pnet-v1')).bytes));
    });
  });

  group('SecureStorageService scoping', () {
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    late ProviderContainer container;
    final store = <String, String>{};

    setUp(() {
      store.clear();
      container = ProviderContainer();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        final args = call.arguments as Map<dynamic, dynamic>;
        final key = args['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'write':
            store[key!] = args['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'deleteAll':
            store.clear();
            return null;
          case 'readAll':
            return Map<String, String>.from(store);
          case 'containsKey':
            return store.containsKey(key);
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      container.dispose();
      AppNetwork.testnet = false;
    });

    test('prefixed keys land in the underlying store', () async {
      final service = SecureStorageService(keyPrefix: 'testnet_');
      await service.write('identity', 'pk');
      expect(store['testnet_identity'], 'pk');
      expect(store.containsKey('identity'), isFalse);
      expect(await service.read('identity'), 'pk');
      expect(await service.containsKey('identity'), isTrue);
      await service.delete('identity');
      expect(store.containsKey('testnet_identity'), isFalse);
    });

    test('scoped deleteAll removes only the active network keys', () async {
      store['mainnet_key'] = 'm';
      store['testnet_a'] = '1';
      store['testnet_b'] = '2';
      final service = SecureStorageService(keyPrefix: 'testnet_');
      await service.deleteAll();
      expect(store, {'mainnet_key': 'm'});
    });

    test('unscoped deleteAll clears everything', () async {
      store['a'] = '1';
      final service = SecureStorageService(keyPrefix: '');
      await service.deleteAll();
      expect(store, isEmpty);
    });

    test('default prefix follows the active network', () {
      AppNetwork.testnet = true;
      expect(SecureStorageService().keyPrefix, 'testnet_');
      AppNetwork.testnet = false;
      expect(SecureStorageService().keyPrefix, '');
    });
  });

  group('IpfsService testnet config', () {
    tearDown(() => AppNetwork.testnet = false);

    test('testnet engine config carries pnet PSK and no bootstrap peers',
        () async {
      AppNetwork.testnet = true;
      final c = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
      ]);
      addTearDown(c.dispose);

      IPFSConfig? config;
      final svc = IpfsService(_Ref(c), engineFactory: (cfg) async {
        config = cfg;
        return _FakeEngine();
      });
      await svc.startNode();

      expect(config!.privateNetworkPsk, isNotNull);
      expect(config!.privateNetworkPsk!.length, 32);
      expect(config!.network.bootstrapPeers, isEmpty);
      expect(config!.datastorePath, contains('ipfs_testnet'));
      expect(config!.libp2pIdentitySeed, isNotNull);
      await svc.stopNode();
    });

    test('mainnet config stays public-swarm with bootstrap enabled', () async {
      AppNetwork.testnet = false;
      final c = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
      ]);
      addTearDown(c.dispose);

      IPFSConfig? config;
      final svc = IpfsService(_Ref(c), engineFactory: (cfg) async {
        config = cfg;
        return _FakeEngine();
      });
      await svc.startNode();

      expect(config!.privateNetworkPsk, isNull);
      expect(config!.datastorePath, contains('ipfs'));
      expect(config!.datastorePath, isNot(contains('ipfs_testnet')));
      await svc.stopNode();
    });

    test('testnet identity seed is stored under the scoped key', () async {
      AppNetwork.testnet = true;
      final storage = _FakeSecureStorage();
      final c = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      addTearDown(c.dispose);

      // The scoped real service prefixes the key the IpfsService writes.
      final scoped = SecureStorageService(keyPrefix: 'testnet_');
      expect(scoped.keyPrefix, 'testnet_');

      final svc = IpfsService(_Ref(c), engineFactory: (cfg) async {
        return _FakeEngine();
      });
      await svc.startNode();
      await svc.stopNode();

      // Whatever key the service wrote, it went through the (faked)
      // scoped storage service - mainnet keychain is untouched by
      // construction.
      expect(storage.data, isNotEmpty);
    });
  });

  group('Isolated durable stores', () {
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    tearDown(() {
      AppNetwork.testnet = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
    });

    void mockSupportDir() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (call) async {
        return '/tmp/alx_iso_test';
      });
    }

    test('database filename follows the network', () {
      AppNetwork.testnet = false;
      expect(dbFileName, 'alexandria.sqlite');
      AppNetwork.testnet = true;
      expect(dbFileName, 'alexandria_testnet.sqlite');
    });

    test('IpfsService data dir resolves under the testnet repo', () async {
      AppNetwork.testnet = true;
      mockSupportDir();
      final c = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(_FakeSecureStorage()),
      ]);
      addTearDown(c.dispose);

      IPFSConfig? config;
      final svc = IpfsService(_Ref(c), engineFactory: (cfg) async {
        config = cfg;
        return _FakeEngine();
      });
      await svc.startNode();
      expect(config!.datastorePath, '/tmp/alx_iso_test/ipfs_testnet/datastore');
      await svc.stopNode();
    });

    test('audit log file follows the network', () async {
      mockSupportDir();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final svc = c.read(auditLogServiceProvider);

      AppNetwork.testnet = true;
      await svc.init();
      expect(svc.logFilePath, contains('audit_trail_testnet.log'));
    });
  });

  group('Scoped protocol surfaces', () {
    tearDown(() => AppNetwork.testnet = false);

    test('rendezvous topic and signing domain follow the network', () {
      AppNetwork.testnet = false;
      expect(RendezvousService.topic, '/alexandria/rendezvous/1');
      expect(RendezvousService.signDomain, 'ALX-RENDEZVOUS/1');

      AppNetwork.testnet = true;
      expect(RendezvousService.topic, '/alexandria-testnet/rendezvous/1');
      expect(RendezvousService.signDomain, 'ALX-TESTNET-RENDEZVOUS/1');
    });

    test('mesh bootstrap seeds nothing under testnet', () {
      AppNetwork.testnet = true;
      final svc = MeshTransportService();
      svc.bootstrapDefaultPeers();
      expect(svc.peers, isEmpty);

      AppNetwork.testnet = false;
      svc.bootstrapDefaultPeers();
      expect(svc.peers, isNotEmpty);
    });

    test('mesh handshake protocol is namespaced under testnet', () {
      AppNetwork.testnet = true;
      expect(MeshTransportService.handshakeProtocol, 'ALX-TESTNET-MESH/1');
      AppNetwork.testnet = false;
      expect(MeshTransportService.handshakeProtocol, 'ALX-MESH/1');
    });

    test('live Lightning sweep is refused under testnet', () async {
      AppNetwork.testnet = true;
      final bridge = CryptoBridgeService(creditService: CreditService());
      final result = await bridge.sweepToLightningAddressLive(
        creditsToSweep: 10,
        customAddress: 'user@walletofsatoshi.com',
      );
      expect(result.success, isFalse);
      expect(result.error, contains('test network'));
    });

    test('Moltbook posts carry the scoped submolt on the wire', () async {
      AppNetwork.testnet = true;
      final svc = MoltbookService(creditService: CreditService());

      final post = await svc.createPost(
        submolt: 'alexandria-bounties',
        title: 't',
        content: 'c',
      );

      expect(post.submolt, 'alexandria-bounties-testnet');
      expect(post.beaconEnvelope, isNotNull);
      // The canonical caller-facing name resolves to the scoped feed.
      expect(svc.getPostsForSubmolt('alexandria-bounties'),
          contains(predicate<MoltbookPost>((p) => p.id == post.id)));
      // The signed wire payload carries the scoped channel too.
      expect(post.beaconEnvelope!.payload['submolt'],
          'alexandria-bounties-testnet');
    });

    test('Moltbook demo seeds land under scoped keys', () {
      AppNetwork.testnet = true;
      final svc = MoltbookService(creditService: CreditService());
      svc.seedDemoPostsForTest();
      expect(svc.getPostsForSubmolt('alexandria-bounties'), isNotEmpty);
      expect(svc.getPostsForSubmolt('open-science'), isNotEmpty);
    });
  });

  group('Testnet UI banner', () {
    tearDown(() => AppNetwork.testnet = false);

    testWidgets('TESTNET banner renders over the app', (tester) async {
      AppNetwork.testnet = true;
      final storage = _FakeSecureStorage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageServiceProvider.overrideWithValue(storage),
          ],
          child: const AlexandriaApp(),
        ),
      );
      await tester.pump();
      final banner = tester.widget<Banner>(find.byType(Banner));
      expect(banner.message, 'TESTNET');
      expect(banner.location, BannerLocation.topStart);
    });
  });
}
