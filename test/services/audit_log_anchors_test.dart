// Campaign-2 tests: audit-log redundant head anchors.
//
// The chain head used to live ONLY in secure storage — an attacker
// with secure-storage WRITE could delete it and truncate the log
// undetectably. Now the head is persisted redundantly:
//   * a MAC'd sidecar file (<log>.head) rewritten on every signed
//     write — the reader takes the higher-seq anchor of
//     {storage, sidecar};
//   * periodic in-file checkpoint lines, MAC'd and chain-linked like
//     ordinary entries;
//   * anomaly markers: 'audit_log_anchor_conflict' and
//     'audit_log_head_anchor_missing'.
// Residual documented in the service: a persistent attacker with a
// captured older anchor pair can still roll back BOTH consistently —
// closing that needs an external anchor.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/secure_storage_service.dart';

class _FakeSecureStorage implements SecureStorageService {
  final Map<String, String> _data = {};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async => _data[key] = value;
  @override
  Future<void> delete(String key) async => _data.remove(key);
  @override
  Future<void> deleteAll() async => _data.clear();
  @override
  Future<bool> containsKey(String key) async => _data.containsKey(key);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuditLogService head anchors (campaign-2)', () {
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    final keyBytes = utf8.encode('test-master-key-0123456789abcdef');
    late ProviderContainer container;
    late _FakeSecureStorage storage;
    late Directory tempDir;
    late AuditLogService service;

    File logFile() => File('${tempDir.path}/audit_trail.log');
    File headFile() => File('${tempDir.path}/audit_trail.log.head');

    AuditLogService svc({int checkpointEvery = 4}) => container.read(
          Provider((ref) =>
              AuditLogService(ref, checkpointEvery: checkpointEvery)),
        );

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audit_anchor_test');
      storage = _FakeSecureStorage();
      storage._data['master_key_v1'] = base64Encode(keyBytes);
      container = ProviderContainer(overrides: [
        secureStorageServiceProvider.overrideWithValue(storage),
      ]);
      service = svc();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      container.dispose();
      await tempDir.delete(recursive: true);
    });

    Future<void> writeEntries(AuditLogService s, int n,
        {String prefix = 'ev'}) async {
      for (var i = 0; i < n; i++) {
        await s.log('${prefix}_$i', details: 'entry $i');
      }
    }

    test('signed writes persist a MAC\'d sidecar head anchor', () async {
      await writeEntries(service, 3);
      expect(await headFile().exists(), isTrue);
      final parts = (await headFile().readAsString()).trim().split('|');
      expect(parts.length, equals(4));
      expect(parts[0], equals('v1'));
      expect(parts[1], equals('2')); // head seq = last entry
      final mac = Hmac(sha256, keyBytes)
          .convert(utf8.encode('audit-head:v1|${parts[1]}|${parts[2]}'))
          .toString();
      expect(parts[3], equals(mac));
    });

    test('in-file checkpoint lines are written every checkpointEvery '
        'entries, chained, and verify on read', () async {
      await writeEntries(service, 4); // checkpointEvery = 4
      final lines = await logFile().readAsLines();
      expect(lines.length, equals(5)); // 4 entries + 1 checkpoint
      expect(lines[4], contains('audit_chain_checkpoint'));

      final logs = await service.getRecentLogs(20);
      final ckpt = logs.where((l) => l.event == 'audit_chain_checkpoint');
      expect(ckpt.length, equals(1));
      expect(ckpt.first.status, equals('Checkpoint'));
      expect(ckpt.first.actor, equals('system'));
      // No tamper flags on an honest read.
      expect(logs.where((l) => l.status == 'Tampered'), isEmpty);
    });

    test('a checkpoint whose recorded head lies is flagged tampered '
        'even with a valid MAC', () async {
      await writeEntries(service, 4);
      final lines = await logFile().readAsLines();
      // Craft a checkpoint line at index 4 with a VALID MAC but a
      // recorded head digest that does not match line 3 — exercises
      // the recorded-head consistency check independently of the MAC.
      final ts = DateTime.now().toIso8601String();
      final prevDigest =
          sha256.convert(utf8.encode(lines[3].trim())).toString();
      final input = 'v2|4|$prevDigest|$ts|audit_chain_checkpoint|'
          '3:${'b' * 64}|system|Checkpoint';
      final mac = Hmac(sha256, keyBytes)
          .convert(utf8.encode(input))
          .toString();
      lines[4] = '$ts|audit_chain_checkpoint|3:${'b' * 64}'
          '|v2:4:$prevDigest:$mac|system|Checkpoint';
      await logFile().writeAsString('${lines.join('\n')}\n');
      final logs = await service.getRecentLogs(20);
      final ckpt =
          logs.where((l) => l.event == 'audit_chain_checkpoint');
      expect(ckpt.isNotEmpty, isTrue);
      expect(ckpt.first.status, equals('Tampered'));
    });

    test('storage-head deletion alone no longer blinds truncation '
        'detection — the sidecar anchor still exposes the gap',
        () async {
      await writeEntries(service, 3);
      // Attacker: deletes the secure-storage head and truncates the
      // tail — but cannot touch the sidecar.
      await storage.delete('audit_chain_head_v1');
      final lines = await logFile().readAsLines();
      await logFile().writeAsString('${lines.first}\n');

      // Fresh service instance: no in-memory head, anchors resolve
      // from disk — the sidecar still reports seq 2.
      final fresh = svc();
      final logs = await fresh.getRecentLogs(20);
      final gaps = logs.where((l) => l.event == 'audit_log_tail_gap');
      expect(gaps, isNotEmpty,
          reason: 'deleting the storage head must not blind truncation '
              'detection — the sidecar anchor still knows the head');
      expect(gaps.every((l) => l.status == 'Tampered'), isTrue);
    });

    test('deleting EVERY anchor while signed lines remain is itself '
        'surfaced (audit_log_head_anchor_missing)', () async {
      await writeEntries(service, 3);
      // Attacker: deletes BOTH anchors and truncates the tail.
      await storage.delete('audit_chain_head_v1');
      await headFile().delete();
      final lines = await logFile().readAsLines();
      await logFile().writeAsString('${lines.first}\n');

      final fresh = svc();
      final logs = await fresh.getRecentLogs(20);
      expect(
        logs.any((l) =>
            l.event == 'audit_log_head_anchor_missing' &&
            l.status == 'Tampered'),
        isTrue,
        reason: 'with no anchor left, the missing anchors must be '
            'visible rather than silently accepted',
      );
    });

    test('a corrupted sidecar degrades to absent — storage anchor '
        'still detects truncation', () async {
      await writeEntries(service, 3);
      await headFile().writeAsString('v1|2|deadbeef|${'0' * 64}\n');
      final lines = await logFile().readAsLines();
      await logFile().writeAsString('${lines.first}\n');

      final fresh = svc();
      final logs = await fresh.getRecentLogs(20);
      expect(logs.any((l) => l.event == 'audit_log_tail_gap'), isTrue,
          reason: 'the surviving storage anchor still exposes the '
              'truncation even with the sidecar corrupted');
      expect(
          logs.any((l) => l.event == 'audit_log_head_anchor_missing'),
          isFalse);
    });

    test('a same-seq/different-digest anchor disagreement is flagged '
        '(audit_log_anchor_conflict)', () async {
      await writeEntries(service, 3);
      // Attacker rewrites ONLY the storage anchor: same seq, forged
      // digest — impossible for honest writes.
      storage._data['audit_chain_head_v1'] = '2:${'a' * 64}';
      final logs = await service.getRecentLogs(20);
      expect(
        logs.any((l) =>
            l.event == 'audit_log_anchor_conflict' &&
            l.status == 'Tampered'),
        isTrue,
      );
    });

    test('unsigned (nosig) files write no anchors and raise no flags',
        () async {
      storage._data.remove('master_key_v1');
      await writeEntries(service, 5);
      expect(await headFile().exists(), isFalse);
      final logs = await service.getRecentLogs(20);
      expect(
          logs.any((l) => l.event == 'audit_log_head_anchor_missing'),
          isFalse);
      expect(logs.any((l) => l.event == 'audit_chain_checkpoint'),
          isFalse);
    });

    test('fresh instance recovers expected head from in-file '
        'checkpoint when every external anchor is gone', () async {
      await writeEntries(service, 4); // checkpoint at index 4
      await storage.delete('audit_chain_head_v1');
      await headFile().delete();
      // Truncate the tail back TO the checkpoint — the recovered
      // checkpoint becomes the remembered head; further truncation
      // below it is detectable by the next read.
      final lines = await logFile().readAsLines();
      await logFile()
          .writeAsString('${lines.sublist(0, 5).join('\n')}\n');

      final fresh = svc();
      // First read anchors the head on the checkpoint.
      await fresh.getRecentLogs(20);
      // Attacker now truncates below the checkpoint.
      await logFile().writeAsString('${lines.first}\n');
      final logs = await fresh.getRecentLogs(20);
      expect(
          logs.any((l) =>
              l.event == 'audit_log_tail_gap' ||
              l.event == 'audit_log_head_anchor_missing'),
          isTrue);
    });
  });
}
