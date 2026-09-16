import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/services/agent/mcp_stdio_runner.dart';
import 'package:alexandria/services/encryption_service.dart';
import 'package:alexandria/services/identity_service.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/ledger_service.dart';
import 'package:alexandria/services/mesh_transport_service.dart';
import 'package:alexandria/services/network_overview_service.dart';
import 'package:alexandria/services/plugin_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:alexandria/services/tor_service.dart';
import 'package:alexandria/services/web_node_service.dart';

import '../network_test_fakes.dart';

/// An executable plugin that can be told to throw from executeAction /
/// onHook, and to carry a malformed (duplicate) permission set.
class _FakePlugin implements AlexandriaPlugin {
  bool throwOnAction = false;
  bool throwOnHook = false;
  bool enabled = true;
  List<PluginPermission> permissions = [PluginPermission.contentRead];

  @override
  PluginManifest get manifest => PluginManifest(
        id: 'test.fake-plugin',
        name: 'Fake',
        version: '1.0.0',
        author: 't',
        description: 'd',
        entrypoint: 'e.wasm',
        permissions: permissions,
        hooks: [PluginHook.onStartup],
      );

  @override
  bool get isEnabled => enabled;

  @override
  set isEnabled(bool value) => enabled = value;

  @override
  Future<void> initialize(PluginContext context) async {}

  @override
  List<PluginActionDefinition> get actions => const [];

  @override
  Future<PluginActionResult> executeAction(
      String actionId, Map<String, dynamic> parameters) async {
    if (throwOnAction) throw StateError('action exploded');
    return PluginActionResult.ok('done');
  }

  @override
  Future<void> onHook(PluginHook hook, dynamic payload) async {
    if (throwOnHook) throw StateError('hook exploded');
  }
}

ProviderContainer _netContainer() => ProviderContainer(
      overrides: [
        ipfsServiceProvider.overrideWith((ref) => FakeIpfsService(ref)),
        meshTransportServiceProvider.overrideWith(
          (ref) => FakeMeshTransportService(),
        ),
        webNodeServiceProvider.overrideWith((ref) => FakeWebNodeService(ref)),
        syncServiceProvider.overrideWith((ref) => FakeSyncService(ref)),
        secureStorageServiceProvider.overrideWith(
          (ref) => FakeSecureStorageService(),
        ),
        torServiceProvider.overrideWith(
          (ref) => FakeTorService(ref.read(secureStorageServiceProvider)),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LedgerService serialization extras', () {
    test('CrossSignature toJson/fromJson round-trips', () {
      final cs = CrossSignature(
        signerPublicKey: Uint8List.fromList(List.filled(32, 0x11)),
        signature: Uint8List.fromList(List.filled(64, 0x22)),
        timestamp: DateTime(2026, 3, 3),
      );
      final restored = CrossSignature.fromJson(cs.toJson());
      expect(restored.signerPublicKey, cs.signerPublicKey);
      expect(restored.signature, cs.signature);
      expect(restored.timestamp, cs.timestamp);
    });

    test(
        'LedgerEntry.fromJson falls back for unknown action and '
        'missing crossSignatures', () {
      final json = {
        'index': 3,
        'timestamp': DateTime(2026, 3, 4).toIso8601String(),
        'action': 'no_such_action',
        'contentCid': 'bafk_x',
        'previousHash': base64Encode(List.filled(32, 0x33)),
        'signature': base64Encode(List.filled(64, 0x44)),
      };
      final entry = LedgerEntry.fromJson(json);
      expect(entry.action, LedgerActionType.pinContent);
      expect(entry.crossSignatures, isEmpty);
    });
  });

  group('PluginService uncovered branches', () {
    test(
        'installPlugin accepts a manifest without '
        'permissions/hooks/uiSlots keys', () {
      final service = PluginService();
      final result = service.installPlugin(jsonEncode({
        'id': 'test.minimal',
        'name': 'Minimal',
        'version': '0.1.0',
        'author': 'a',
        'description': 'd',
        'entrypoint': 'm.wasm',
      }));
      expect(result, isNotNull);
      expect(result!.manifest.permissions, isEmpty);
      expect(result.manifest.hooks, isEmpty);
      expect(result.manifest.uiSlots, isEmpty);
    });

    test(
        'installPlugin decodes permissions/hooks/uiSlots arrays and '
        'manifest toJson round-trips', () {
      final service = PluginService();
      final installed = service.installPlugin(jsonEncode({
        'id': 'test.full',
        'name': 'Full',
        'version': '1.0.0',
        'author': 'a',
        'description': 'd',
        'entrypoint': 'f.wasm',
        'permissions': ['contentRead'],
        'hooks': ['onStartup'],
        'uiSlots': ['settingsSection'],
        'maxMemoryMb': 32,
        'timeoutMs': 1000,
      }));
      expect(installed, isNotNull);
      expect(installed!.manifest.permissions,
          contains(PluginPermission.contentRead));
      expect(installed.manifest.hooks, contains(PluginHook.onStartup));
      expect(installed.manifest.uiSlots, contains(UISlot.settingsSection));

      final json = installed.manifest.toJson();
      expect(json['permissions'], contains('contentRead'));
      expect(json['hooks'], contains('onStartup'));
      expect(json['uiSlots'], contains('settingsSection'));
      expect(installed.name, 'Full');

      // Duplicate install is refused.
      expect(
          service.installPlugin(jsonEncode({
            'id': 'test.full',
            'name': 'Full',
            'version': '1.0.0',
            'author': 'a',
            'description': 'd',
            'entrypoint': 'f.wasm',
          })),
          isNull);
      // Malformed JSON is refused.
      expect(service.installPlugin('{broken'), isNull);
    });

    test('plugin list accessors, toggling and uninstalling', () async {
      final service = PluginService();
      final plugin = _FakePlugin();
      service.registerPlugin(plugin);
      expect(service.getExecutablePlugin('test.fake-plugin'), isNotNull);
      expect(service.executablePlugins, isNotEmpty);
      expect(service.enabledPlugins.map((p) => p.id),
          contains('test.fake-plugin'));
      expect(service.plugins.map((p) => p.id), contains('test.fake-plugin'));

      // Re-registering syncs the existing installed entry's flag.
      plugin.enabled = false;
      service.registerPlugin(plugin);
      final installed =
          service.plugins.firstWhere((p) => p.id == 'test.fake-plugin');
      expect(installed.enabled, isFalse);

      // Disabled plugin cannot execute.
      final disabled =
          await service.executeAction('test.fake-plugin', 'any', const {});
      expect(disabled.success, isFalse);
      expect(disabled.message, contains('disabled'));

      // Unknown plugin cannot execute or toggle.
      final missing =
          await service.executeAction('test.unknown', 'any', const {});
      expect(missing.success, isFalse);
      expect(missing.message, contains('not found'));
      expect(service.togglePlugin('test.unknown', true), isFalse);

      // Toggle back on through the service.
      expect(service.togglePlugin('test.fake-plugin', true), isTrue);
      expect(
          service.getExecutablePlugin('test.fake-plugin')!.isEnabled, isTrue);

      // Hook/slot filtered views.
      expect(service.getPluginsWithHook(PluginHook.onStartup), isNotEmpty);
      expect(service.getPluginsWithHook(PluginHook.onSearch), isEmpty);
      // The built-in DOI harvester occupies the settings slot; an
      // unoccupied slot filters to empty.
      expect(service.getPluginsForSlot(UISlot.settingsSection), isNotEmpty);
      expect(service.getPluginsForSlot(UISlot.homeHeader), isEmpty);

      // Uninstall both branches.
      expect(service.uninstallPlugin('test.unknown'), isFalse);
      expect(service.uninstallPlugin('test.fake-plugin'), isTrue);
      expect(service.getExecutablePlugin('test.fake-plugin'), isNull);
    });

    test('theme install/activate and connector templates', () {
      final service = PluginService();
      expect(service.themes, isEmpty);
      expect(service.activeTheme, isNull);

      final theme = service.installTheme(jsonEncode({
        'id': 'theme.one',
        'name': 'One',
        'version': '1.0.0',
        'author': 'a',
        'colors': {'primary': '#fff'},
        'sizing': {'radius': 4.0},
        'fontFamily': 'Fira',
      }));
      expect(theme, isNotNull);
      expect(theme!.fontFamily, 'Fira');
      final themeJson = theme.toJson();
      expect(themeJson['fontFamily'], 'Fira');
      final restored = ThemeManifest.fromJson(themeJson);
      expect(restored.id, 'theme.one');

      // Duplicate and malformed installs are refused.
      expect(
          service.installTheme(jsonEncode({
            'id': 'theme.one',
            'name': 'One',
            'version': '1.0.0',
            'author': 'a',
            'colors': <String, String>{},
          })),
          isNull);
      expect(service.installTheme('{broken'), isNull);

      // Activate valid + invalid theme ids.
      expect(service.setActiveTheme('theme.one'), isTrue);
      expect(service.activeTheme!.id, 'theme.one');
      expect(service.setActiveTheme('theme.missing'), isFalse);

      // Connector templates decode into installable manifests.
      for (final template in [
        service.zoteroConnectorTemplate,
        service.calibreConnectorTemplate
      ]) {
        final installed = service.installPlugin(template);
        expect(installed, isNotNull);
        expect(installed!.manifest.permissions, isNotEmpty);
      }
    });

    test('registerPlugin refuses a malformed permission set', () {
      final service = PluginService();
      final plugin = _FakePlugin()
        ..permissions = [
          PluginPermission.contentRead,
          PluginPermission.contentRead, // duplicate → invalid
        ];
      service.registerPlugin(plugin);
      expect(service.getExecutablePlugin('test.fake-plugin'), isNull);
    });

    test('executeAction surfaces a throwing plugin as an error result',
        () async {
      final service = PluginService();
      final plugin = _FakePlugin()..throwOnAction = true;
      service.registerPlugin(plugin);
      final result =
          await service.executeAction('test.fake-plugin', 'any', const {});
      expect(result.success, isFalse);
      expect(result.message, contains('Execution exception'));
    });

    test('dispatchHook swallows a throwing plugin hook', () async {
      final service = PluginService();
      final plugin = _FakePlugin()..throwOnHook = true;
      service.registerPlugin(plugin);
      // Must not rethrow — the failing plugin is logged and skipped.
      await service.dispatchHook(PluginHook.onStartup, {'x': 1});
    });
  });

  group('EncryptionService key-material decoding', () {
    test('encryptForPeer resolves base58, base64 and hex key spellings',
        () async {
      final service = EncryptionService();
      final data = Uint8List.fromList(utf8.encode('payload'));
      final pub = List<int>.generate(32, (i) => (i * 7) & 0xFF);

      // Base58 — the AlexandriaIdentity spelling.
      final base58 = AlexandriaIdentity(
        publicKey: Uint8List.fromList(pub),
        privateKey: Uint8List(64),
        createdAt: DateTime(2026, 1, 1),
      ).publicKeyBase58;
      expect(await service.encryptForPeer(data, 'x25519:$base58'), isNotEmpty);

      // Base64.
      final b64 = base64Encode(pub);
      expect(await service.encryptForPeer(data, 'x25519:$b64'), isNotEmpty);

      // Hex.
      final hex = pub.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(await service.encryptForPeer(data, 'x25519:$hex'), isNotEmpty);
    });

    test('Ed25519→X25519 helpers reject wrong-length input', () {
      expect(() => EncryptionService.ed25519PublicToX25519(Uint8List(16)),
          throwsArgumentError);
      expect(() => EncryptionService.ed25519SeedToX25519Seed(Uint8List(16)),
          throwsArgumentError);
    });
  });

  group('NetworkOverviewService tor relay parsing', () {
    late ProviderContainer container;
    late NetworkOverviewService service;

    setUp(() {
      container = _netContainer();
      service = container.read(networkOverviewServiceProvider);
    });

    tearDown(() => container.dispose());

    test('updateTransport parses bracketed, bare and malformed relays',
        () async {
      final tor = container.read(torServiceProvider) as FakeTorService;

      // Bracketed IPv6 with port.
      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: false,
        port: 9150,
        relay: '[::1]:9150',
      ));
      expect(tor.proxyAddress, '[::1]:9150');

      // Bare IPv6 literal — re-bracketed for the setProxy grammar.
      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: false,
        port: 9151,
        relay: '::1',
      ));
      expect(tor.proxyAddress, '[::1]:9151');

      // Malformed bracketed relay → loopback default.
      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: false,
        port: 9152,
        relay: '[::1',
      ));
      expect(tor.proxyAddress, '127.0.0.1:9152');

      // Bracketed IPv6 with a non-numeric tail → loopback default.
      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: false,
        port: 9153,
        relay: '[::1]:nope',
      ));
      expect(tor.proxyAddress, '127.0.0.1:9153');

      // host:port and bare host pass through.
      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: false,
        port: 9154,
        relay: 'relay.example:9154',
      ));
      expect(tor.proxyAddress, 'relay.example:9154');
      await service.updateTransport(const TransportConfig(
        protocol: TransportProtocol.tor,
        enabled: false,
        port: 9155,
        relay: 'relay.example',
      ));
      expect(tor.proxyAddress, 'relay.example:9155');
    });

    test('testConnections reports a reachable tor proxy', () async {
      // A real TorService pointed at a live loopback socket exercises
      // the 'Tor: proxy reachable' branch.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final tor = TorService(FakeSecureStorageService());
      await tor.setProxy('127.0.0.1', server.port);
      expect(await tor.enable(), isTrue);

      final live = ProviderContainer(overrides: [
        ipfsServiceProvider.overrideWith((ref) => FakeIpfsService(ref)),
        webNodeServiceProvider.overrideWith((ref) => FakeWebNodeService(ref)),
        torServiceProvider.overrideWithValue(tor),
      ]);
      addTearDown(live.dispose);
      final result =
          await live.read(networkOverviewServiceProvider).testConnections();
      expect(result, contains('Tor: proxy reachable'));
    });
  });

  group('AlexandriaMcpRunner token channels and socket auth', () {
    AlexandriaMcpRunner runner() => AlexandriaMcpRunner(
          sessionToken: 'tok-test',
          listTools: () => const [],
          callTool: (name, args) async => const {'ok': true},
        );

    test('token accepted under params.session_token', () async {
      final r = runner();
      final res = await r.handleJsonRpcRequest({
        'id': 1,
        'method': 'ping',
        'params': {'session_token': 'tok-test'},
      });
      expect(res?['result'], isNotNull);
    });

    test('malformed first frame closes the control connection', () async {
      final socket = McpControlSocket(runner());
      final port = await socket.start();
      addTearDown(socket.close);

      final conn = await Socket.connect(InternetAddress.loopbackIPv4, port);
      final closed = Completer<void>();
      conn.listen(
        (_) {},
        onDone: closed.complete,
        onError: (_) => closed.complete(),
        cancelOnError: true,
      );
      conn.writeln('definitely not json');
      await conn.flush();
      // Server must destroy the connection on an unparseable auth frame.
      await closed.future.timeout(const Duration(seconds: 5));
    });
  });
}
