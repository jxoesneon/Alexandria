import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/providers/library_providers.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/external_player_service.dart';
import 'package:alexandria/services/identity_service.dart';

/// Stateful in-memory handler for flutter_secure_storage.
Map<String, String> installSecureStore() {
  final store = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async {
      final key = call.arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return store[key];
        case 'write':
          store[key!] = call.arguments['value'] as String;
          return null;
        case 'delete':
          store.remove(key);
          return null;
        case 'containsKey':
          return store.containsKey(key);
        default:
          return null;
      }
    },
  );
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExternalPlayerService', () {
    final service = ExternalPlayerService();

    test('isSafeExternalTarget rejects dangerous inputs', () {
      expect(ExternalPlayerService.isSafeExternalTarget(''), isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('x' * 4097), isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('a;b'), isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('a|b'), isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('a`id`'), isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('a\nb'), isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('-rf'), isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('--foo'), isFalse);
      expect(
          ExternalPlayerService.isSafeExternalTarget('file:///etc/passwd'),
          isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('javascript:x'),
          isFalse);
      expect(ExternalPlayerService.isSafeExternalTarget('data:abc'), isFalse);
      // Backslash-laden drive paths are excluded by the metachar ban.
      expect(ExternalPlayerService.isSafeExternalTarget(r'C:\temp\f'), isFalse);
    });

    test('isSafeExternalTarget accepts http(s) and plain paths', () {
      expect(ExternalPlayerService.isSafeExternalTarget('https://x.io/f'),
          isTrue);
      expect(ExternalPlayerService.isSafeExternalTarget('http://x.io'), isTrue);
      expect(ExternalPlayerService.isSafeExternalTarget('/tmp/file.epub'),
          isTrue);
      expect(ExternalPlayerService.isSafeExternalTarget('relative/doc.pdf'),
          isTrue);
    });

    test('buildVlcCommand validates target and applies options', () {
      expect(() => service.buildVlcCommand('bad;target'),
          throwsArgumentError);
      final args = service.buildVlcCommand(
        '/tmp/movie.mp4',
        options: const VlcPlaybackOptions(
          fullscreen: true,
          loop: true,
          subtitlePath: '/tmp/s.srt',
          equalizerPreset: 'flat',
          startTimeSeconds: 12,
          audioTrackIndex: 2,
          httpControlPort: 8080,
        ),
      );
      final joined = args.join(' ');
      expect(joined, contains('--fullscreen'));
      expect(joined, contains('--loop'));
      expect(joined, contains('--sub-file=/tmp/s.srt'));
      expect(joined, contains('--equalizer-preset=flat'));
      expect(joined, contains('--start-time=12'));
      expect(joined, contains('--audio-track=2'));
      expect(joined, contains('--extraintf=http'));
      expect(joined, contains('--http-port=8080'));
    });

    test('custom executable path is honored', () {
      service.setCustomAppPath(SupportedApp.vlc, '/opt/vlc/bin/vlc');
      expect(service.getCustomAppPath(SupportedApp.vlc), '/opt/vlc/bin/vlc');
      expect(service.getCustomAppPath(SupportedApp.blender), isNull);
      final args = service.buildVlcCommand('/tmp/m.mp4');
      if (!Platform.isMacOS && !Platform.isWindows) {
        expect(args.first, '/opt/vlc/bin/vlc');
      }
    });

    test('buildAppCommand covers each app on the host platform', () {
      for (final app in SupportedApp.values) {
        final args = service.buildAppCommand(app, '/tmp/file.xyz',
            extraArgs: const ['--extra']);
        expect(args, isNotEmpty);
        expect(args.contains('/tmp/file.xyz'), isTrue);
      }
      expect(() => service.buildAppCommand(SupportedApp.calibre, 'a;b'),
          throwsArgumentError);
    });
  });

  group('AuditLogService', () {
    late Directory logDir;
    late Map<String, String> store;
    late ProviderContainer container;
    late AuditLogService service;

    setUp(() async {
      store = installSecureStore();
      logDir = await Directory.systemTemp.createTemp('audit_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return logDir.path;
          }
          return null;
        },
      );
      container = ProviderContainer();
      service = container.read(auditLogServiceProvider);
    });

    tearDown(() {
      container.dispose();
      logDir.deleteSync(recursive: true);
      // Restore an unmocked channel so later groups don't write to the
      // deleted temp dir (the handler is process-global).
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });

    File logFile() => File('${logDir.path}/audit_trail.log');

    test('unsigned entries surface flagged Unverified', () async {
      await service.log('test_event', details: 'd', actor: 'me');
      final logs = await service.getRecentLogs(10);
      expect(logs, hasLength(1));
      expect(logs.first.event, 'test_event');
      expect(logs.first.status, 'Unverified');
      expect(logs.first.actor, 'me');
    });

    test('signed entries verify and round-trip escaped fields', () async {
      store['master_key_v1'] = base64Encode(List.filled(32, 9));
      await service.log('signed_event',
          details: 'has | pipe\nand newline', actor: 'actor1');
      final logs = await service.getRecentLogs(10);
      expect(logs, hasLength(1));
      expect(logs.first.status, 'Success');
      expect(logs.first.actor, 'actor1');
      expect(logs.first.event, 'signed_event');
    });

    test('tampered v2 line is flagged, never trusted', () async {
      store['master_key_v1'] = base64Encode(List.filled(32, 9));
      await service.log('real_event', actor: 'victim');
      // Forge an extra signed-looking line with a bad MAC.
      final forged =
          '${DateTime.now().toIso8601String()}|forged|x|v2:1:genesis:deadbeef|attacker|Success\n';
        await logFile().writeAsString(forged, mode: FileMode.append);
      final logs = await service.getRecentLogs(10);
      final forgedEntry = logs.firstWhere((l) => l.event == 'forged');
      expect(forgedEntry.status, 'Tampered');
      expect(forgedEntry.actor, 'unknown');
    });

    test('legacy v1 signed lines verify and bad ones are flagged', () async {
      final key = List.filled(32, 9);
      store['master_key_v1'] = base64Encode(key);
      await service.init();
      final ts = '2024-01-01T00:00:00.000Z';
      final mac = Hmac(sha256, key).convert(utf8.encode('$ts|evt|det'));
      await logFile().writeAsString('$ts|evt|det|$mac\n');
      await logFile()
          .writeAsString('$ts|evt2|det2|bogusmac\n', mode: FileMode.append);
      final logs = await service.getRecentLogs(10);
      expect(logs.any((l) => l.event == 'evt' && l.status == 'Success'),
          isTrue);
      expect(logs.any((l) => l.event == 'evt2' && l.status == 'Tampered'),
          isTrue);
    });

    test('malformed lines are skipped', () async {
      await service.init();
      await logFile().writeAsString('too|short\n');
      final logs = await service.getRecentLogs(10);
      expect(logs, isEmpty);
    });

    test('truncated tail synthesizes gap markers', () async {
      store['master_key_v1'] = base64Encode(List.filled(32, 9));
      await service.log('e1');
      await service.log('e2');
      // Truncate the file — the persisted head says two entries existed.
      await logFile().writeAsString('');
      final logs = await service.getRecentLogs(50);
      expect(logs.where((l) => l.event == 'audit_log_tail_gap'), isNotEmpty);
      expect(logs.first.status, 'Tampered');
    });

    test('non-positive limit clamps to empty', () async {
      expect(await service.getRecentLogs(0), isEmpty);
      expect(await service.getRecentLogs(-3), isEmpty);
    });
  });

  group('IdentityService extras', () {
    late ProviderContainer container;
    late IdentityService service;

    setUp(() {
      installSecureStore();
      container = ProviderContainer();
      service = container.read(identityServiceProvider);
    });

    tearDown(() => container.dispose());

    test('AlexandriaIdentity toJson exposes public fields only', () async {
      final identity = await service.generateIdentity();
      final json = identity.toJson();
      expect(json['publicKey'], identity.publicKeyBase58);
      expect(json['shortId'], identity.shortId);
      expect(json.containsKey('privateKey'), isFalse);
    });

    test('decodePublicKeyBase58 round-trips incl. leading zeroes', () async {
      final identity = await service.generateIdentity();
      final decoded =
          AlexandriaIdentity.decodePublicKeyBase58(identity.publicKeyBase58);
      expect(decoded, identity.publicKey);
      // Leading '1' characters map to leading zero bytes.
      final withZeros = AlexandriaIdentity.decodePublicKeyBase58('11abc');
      expect(withZeros[0], 0);
      expect(withZeros[1], 0);
    });

    test('createIdentityProof requires identity', () async {
      await expectLater(
          () => service.createIdentityProof(), throwsStateError);
      await service.generateIdentity();
      final proof = await service.createIdentityProof();
      expect(proof.signatureBase64, isNotEmpty);
      expect(proof.publicKey, isNotEmpty);
    });

    test('x25519 keys are null without identity, bytes with one', () async {
      expect(await service.x25519PrivateKeyBytes(), isNull);
      expect(await service.x25519PublicKeyBytes(), isNull);
      await service.generateIdentity();
      final priv = await service.x25519PrivateKeyBytes();
      final pub = await service.x25519PublicKeyBytes();
      expect(priv, hasLength(32));
      expect(pub, hasLength(32));
    });
  });

  group('library_providers', () {
    late Map<String, String> store;
    late ProviderContainer container;
    late ContentRepository repo;

    setUp(() {
      store = installSecureStore();
      container = ProviderContainer();
      repo = container.read(contentRepositoryProvider);
    });

    tearDown(() => container.dispose());

    test('readingProgressProvider handles missing/invalid/non-map/valid',
        () async {
      expect(await container.read(readingProgressProvider.future), isEmpty);

      store['reading_progress'] = 'not-json{';
      container.invalidate(readingProgressProvider);
      expect(await container.read(readingProgressProvider.future), isEmpty);

      store['reading_progress'] = '[1,2,3]';
      container.invalidate(readingProgressProvider);
      expect(await container.read(readingProgressProvider.future), isEmpty);

      store['reading_progress'] = jsonEncode({'cidA': 0.5});
      container.invalidate(readingProgressProvider);
      final map = await container.read(readingProgressProvider.future);
      expect(map['cidA'], 0.5);
    });

    test('libraryDashboardProvider aggregates manifests and formats size',
        () async {
      final uuid = await repo.createContent(
          title: 'DashDoc', fileData: utf8.encode('x' * 128));
      final db = container.read(databaseProvider);
      final manifest = await repo.getManifestByUuid(uuid);
      // Force a large version size to exercise _formatBytes MB/GB branches.
      await db.insertVersion({
        'manifestId': manifest!.id,
        'cid': 'bafkreihuge1',
        'language': 'en',
        'format': 'bin',
        'sizeBytes': 5 * 1024 * 1024 * 1024,
        'createdData': DateTime.now(),
      });
      final stats = await container.read(libraryDashboardProvider.future);
      expect(stats.totalItems, 1);
      expect(stats.totalSize, contains('GB'));
      expect(stats.networkStatus, isNotEmpty);
    });

    test('documentVersionsProvider resolves by cid, uuid, and misses',
        () async {
      final uuid = await repo.createContent(
          title: 'Vers', fileData: utf8.encode('v ' * 80));
      final manifest = await repo.getManifestByUuid(uuid);
      final db = container.read(databaseProvider);
      final versions = await db.getVersionsForManifest(manifest!.id);
      final cid = versions.first.cid;

      final byCid =
          await container.read(documentVersionsProvider(cid).future);
      expect(byCid, hasLength(1));
      final byUuid =
          await container.read(documentVersionsProvider(uuid).future);
      expect(byUuid, hasLength(1));
      final miss = await container
          .read(documentVersionsProvider('nope').future);
      expect(miss, isEmpty);
    });

    test('currentDocumentProvider loads by uuid and honors active cid',
        () async {
      final uuid = await repo.createContent(
          title: 'DocTitle',
          fileData: utf8.encode('document body text ' * 5),
          format: 'txt');
      final doc =
          await container.read(currentDocumentProvider(uuid).future);
      expect(doc.title, 'DocTitle');
      expect(doc.content, contains('document body text'));

      // activeVersionCid override selects a specific edition.
      final manifest = await repo.getManifestByUuid(uuid);
      final db = container.read(databaseProvider);
      final versions = await db.getVersionsForManifest(manifest!.id);
      final cid = versions.first.cid;
      final sub = container.listen(
          activeVersionCidProvider(uuid).notifier, (_, __) {});
      container.read(activeVersionCidProvider(uuid).notifier).state = cid;
      final doc2 =
          await container.read(currentDocumentProvider(uuid).future);
      expect(doc2.cid, cid);
      sub.close();

      await expectLater(
        () => container.read(currentDocumentProvider('missing-x').future),
        throwsArgumentError,
      );
    });
  });
}
