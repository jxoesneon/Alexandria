// RED TEAM PoC — AuditLogService signs each entry with an HMAC at
// write time (lib/services/audit_log_service.dart:46-53), but
// getRecentLogs NEVER verifies it: the signature column is parsed and
// discarded (line 74), and `status` is taken straight off the line.
// An attacker who can append to audit_trail.log (or a hostile writer
// of a synced/restored log file) fabricates arbitrary events — e.g.
// 'access_denied ... Denied' to trigger the high-severity alert in
// SecurityOverviewService.getCurrentAlerts, or 'grant_access ...
// Success' to launder a fake ACL grant — and the UI reports them as
// genuine. The HMAC is write-time theatre: tamper-evidence is claimed,
// never enforced.
//
// Asserts the SECURE expectation: an entry whose signature cannot be
// verified must not surface as a trusted 'Success' log — it must be
// dropped or flagged unverified.
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/audit_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audit_rt');
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null, // no key → 'nosig' signatures
    );
  });

  tearDown(() async {
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('a forged log line must not surface as a trusted entry', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final svc = container.read(auditLogServiceProvider);

    // One genuine entry.
    await svc.log('genuine_event', details: 'real', status: 'Success');

    // Attacker appends a forged line straight to the file — bogus
    // signature column, 'Success' status, fake actor.
    final file = File('${tmp.path}/audit_trail.log');
    await file.writeAsString(
      '${DateTime.now().toIso8601String()}|grant_access|'
      'CID: bafyVictim, Peer: did:alex:attacker|'
      '${'0' * 64}|did:alex:attacker|Success\n',
      mode: FileMode.append,
    );

    final logs = await svc.getRecentLogs(10);
    final forged = logs.where((l) => l.event == 'grant_access');
    expect(forged.isEmpty, isTrue,
        reason:
            'a forged line (invalid signature, invented actor) surfaced '
            'in getRecentLogs as a normal entry — the write-side HMAC '
            'is never verified on read, so audit entries provide zero '
            'tamper-evidence. Logs with unverifiable signatures must be '
            'dropped or flagged, not trusted.');
  });
}
