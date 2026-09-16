// RED TEAM PoC — Round-4: the round-3 fix made getRecentLogs verify the
// write-side HMAC — but the MAC covers ONLY parts[0..2]
// (timestamp|event|details):
//
//   lib/services/audit_log_service.dart:93-97
//     final payload = '${parts[0]}|${parts[1]}|${parts[2]}';
//     final expected = Hmac(sha256, keyBytes).convert(...).toString();
//     if (expected != signature) continue;
//     status = parts.length >= 6 ? _unesc(parts[5]) : 'Success';
//
// `actor` (parts[4]) and `status` (parts[5]) are OUTSIDE the MAC. An
// attacker who can append to audit_trail.log takes ANY genuine signed
// line, rewrites the unprotected trailing columns, and the line still
// verifies as a TRUSTED entry — 'Denied' becomes 'Success', 'attacker'
// becomes 'victim'. The round-3 fix authenticates what happened but not
// who it was attributed to or how it ended — the two fields a frame-up
// attack actually changes.
//
// Asserts the SECURE expectation: a line whose actor/status columns were
// tampered must be dropped or flagged — it must not surface trusted.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/audit_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  final hmacKey = base64Encode(List<int>.generate(32, (i) => i));

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audit_rt4');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        // Return the HMAC key for reads of 'master_key_v1' so the
        // service produces SIGNED entries; null for everything else.
        if (call.method == 'read' &&
            (call.arguments as Map)['key'] == 'master_key_v1') {
          return hmacKey;
        }
        return null;
      },
    );
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
      'tampering actor/status columns of a signed line must not pass '
      'the MAC check', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final svc = container.read(auditLogServiceProvider);

    // One genuine SIGNED entry — a denied access attempt by the attacker.
    await svc.log('grant_access',
        details: 'CID: bafySecret',
        actor: 'did:alex:attacker',
        status: 'Denied');

    final file = File('${tmp.path}/audit_trail.log');
    final original = await file.readAsString();
    expect(original.trim().isNotEmpty, isTrue);
    final parts = original.trim().split('|');
    expect(parts.length, greaterThanOrEqualTo(6));

    // Attacker (file-write access — the exact adversary the read-side
    // HMAC was built to stop) rewrites ONLY the unprotected columns:
    // keep timestamp|event|details|hmac intact, flip actor→victim and
    // status→Success. The signed prefix is untouched, so the MAC still
    // verifies — the forged attribution surfaces as trusted.
    final forged = '${parts[0]}|${parts[1]}|${parts[2]}|${parts[3]}'
        '|did:alex:victim|Success\n';
    await file.writeAsString(forged);

    final logs = await svc.getRecentLogs(10);
    final entry = logs.where((l) => l.event == 'grant_access');
    expect(entry, isNotEmpty);

    expect(entry.first.status, isNot('Success'),
        reason: 'a signed line with tampered actor/status surfaced as a '
            'TRUSTED "Success" — the HMAC covers only '
            'timestamp|event|details, so parts[4]/parts[5] are freely '
            'rewritable. An attacker re-attributed a denied grant to '
            'the victim and flipped it to Success without ever touching '
            'the signed prefix.');
    expect(entry.first.actor, isNot('did:alex:victim'),
        reason: 'the actor column is unauthenticated — a forged identity '
            'survived the MAC check verbatim.');
  });

  test('tail truncation is undetectable — no sequence/chain integrity',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final svc = container.read(auditLogServiceProvider);

    await svc.log('event_one', details: 'first');
    await svc.log('event_two', details: 'second');

    final file = File('${tmp.path}/audit_trail.log');
    final lines = await file.readAsLines();
    // Attacker deletes the LAST entry (e.g. the one that incriminates
    // them) — lines carry no sequence number or link, so absence is
    // silent.
    await file.writeAsString('${lines.first}\n');

    final logs = await svc.getRecentLogs(10);
    // SECURE expectation: an audit log must not silently lose its tail.
    // There is no API that reports truncation — the only signal would be
    // a chain/sequence field on surviving lines, which does not exist.
    expect(logs.length, equals(2),
        reason: 'the log silently lost its tail — entries carry no sequence '
            'number or hash link, so deleting the last N lines is '
            'undetectable. The HMAC authenticates surviving lines but '
            'says nothing about ABSENT ones.');
  });
}
