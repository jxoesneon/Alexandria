import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/providers/security_providers.dart';
import 'package:alexandria/services/audit_log_service.dart';
import 'package:alexandria/services/encryption_service.dart';
import 'package:alexandria/services/identity_service.dart';

import '../ui/security/fake_security_overview_service.dart';

// Simple fakes to satisfy override contract; only the provider shapes matter here.
class FakeIdentityService implements IdentityService {
  final StreamController<int> _revisionController =
      StreamController<int>.broadcast(sync: true);

  // identityRevisionProvider is watched by identityStateProvider /
  // activeIdentitiesProvider — the fake must expose a real stream.
  @override
  Stream<int> get revisionStream => _revisionController.stream;

  @override
  int get revision => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeEncryptionService implements EncryptionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuditLogService implements AuditLogService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeSecurityOverviewService fake;
  late ProviderContainer container;

  setUp(() {
    fake = FakeSecurityOverviewService();
    container = ProviderContainer(
      overrides: [
        securityOverviewServiceProvider.overrideWithValue(fake),
        identityServiceProvider.overrideWithValue(FakeIdentityService()),
        encryptionServiceProvider.overrideWithValue(FakeEncryptionService()),
        auditLogServiceProvider.overrideWithValue(FakeAuditLogService()),
      ],
    );
    addTearDown(container.dispose);
  });

  test('securityOverviewProvider reads overview from service', () async {
    const expected = SecurityOverview(score: 82, encryptionEnabled: true);
    fake.overview = expected;
    final overview = await container.read(securityOverviewProvider.future);
    expect(overview, equals(expected));
  });

  test('securityAlertsProvider emits alerts from service', () async {
    final now = DateTime(2024, 5, 1);
    final alerts = [
      SecurityAlert(severity: 'high', message: 'm', timestamp: now),
    ];
    fake.alerts = alerts;
    final emitted = await container.read(securityAlertsProvider.future);
    expect(emitted, equals(alerts));
  });

  test('activeIdentitiesProvider reads identities', () async {
    final identities = [
      Keypair(
        id: 'key-1',
        type: KeyType.ed25519,
        createdAt: DateTime(2024, 5, 1),
        did: 'did:alex:key-1',
      ),
    ];
    fake.identities = identities;
    final result = await container.read(activeIdentitiesProvider.future);
    expect(result, equals(identities));
  });

  test('documentsProvider reads documents', () async {
    const docs = [DocumentOption(cid: 'cid-1', title: 'Doc 1')];
    fake.documents = docs;
    final result = await container.read(documentsProvider.future);
    expect(result, equals(docs));
  });

  test('documentAclProvider reads policies by cid', () async {
    final policies = [
      AccessPolicy(
        cid: 'cid-1',
        peerDid: 'did:alex:p',
        grantedAt: DateTime(2024, 5, 1),
      ),
    ];
    fake.accessPolicies = {'cid-1': policies};
    final result = await container.read(documentAclProvider('cid-1').future);
    expect(result, equals(policies));
  });

  test('auditLogsProvider reads recent logs', () async {
    final logs = [
      AuditLog(
        event: 'grant_access',
        actor: 'a',
        timestamp: DateTime(2024, 5, 1),
        status: 'Success',
      ),
    ];
    fake.auditLogs = logs;
    final result = await container.read(auditLogsProvider.future);
    expect(result, equals(logs));
  });

  test('porChallengesProvider holds initial empty list', () {
    expect(container.read(porChallengesProvider), isEmpty);
  });

  test('selectedCidProvider can be updated', () {
    container.read(selectedCidProvider.notifier).state = 'cid-x';
    expect(container.read(selectedCidProvider), 'cid-x');
  });

  test('peerDidProvider can be updated', () {
    container.read(peerDidProvider.notifier).state = 'did:alex:x';
    expect(container.read(peerDidProvider), 'did:alex:x');
  });

  test('porCidProvider can be updated', () {
    container.read(porCidProvider.notifier).state = 'cid-a';
    expect(container.read(porCidProvider), 'cid-a');
  });

  test('porPeerIdProvider can be updated', () {
    container.read(porPeerIdProvider.notifier).state = 'peer-a';
    expect(container.read(porPeerIdProvider), 'peer-a');
  });

  test('porResultProvider can be updated', () {
    container.read(porResultProvider.notifier).state = 'verified';
    expect(container.read(porResultProvider), 'verified');
  });
}
