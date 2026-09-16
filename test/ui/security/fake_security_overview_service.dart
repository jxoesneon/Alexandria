import 'dart:async';

import 'package:alexandria/models/security_models.dart';
import 'package:alexandria/services/security_overview_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A fake [SecurityOverviewService] for widget tests.
class FakeSecurityOverviewService implements SecurityOverviewService {
  FakeSecurityOverviewService([this.ref]);

  Ref? ref;

  SecurityOverview overview = const SecurityOverview(
    score: 82,
    encryptionEnabled: true,
  );
  List<SecurityAlert> alerts = const [];
  List<Keypair> identities = const [];
  Keypair? generatedIdentity;
  DidDocument resolvedDid = const DidDocument(did: '', publicKeys: []);
  List<DocumentOption> documents = const [];
  Map<String, List<AccessPolicy>> accessPolicies = {};
  List<AuditLog> auditLogs = const [];
  List<PorChallenge> issuedChallenges = const [];
  bool verifyResult = true;

  /// When set, [generateNewKeypair] throws it - simulates a rotation
  /// failure (e.g. post-write verification StateError).
  Object? generateError;

  @override
  Future<SecurityOverview> getOverview() async => overview;

  @override
  Stream<List<SecurityAlert>> watchSecurityAlerts() =>
      Stream.fromFuture(getCurrentAlerts());

  @override
  Future<List<SecurityAlert>> getCurrentAlerts() async => alerts;

  @override
  Future<List<Keypair>> getActiveIdentities() async => identities;

  @override
  Future<Keypair> generateNewKeypair(KeyType type) async {
    final error = generateError;
    if (error != null) throw error;
    generatedIdentity ??= Keypair(
      id: 'key-001',
      type: type,
      createdAt: DateTime(2024, 5, 12),
      did: 'did:alex:key-001',
    );
    identities = [generatedIdentity!];
    return generatedIdentity!;
  }

  @override
  Future<String> exportPrivateKey(String keyId, String password) async {
    return 'encrypted-private-key-$keyId-${password.hashCode}';
  }

  @override
  Future<DidDocument> resolveDid(String did) async => resolvedDid;

  @override
  Future<List<DocumentOption>> getDocuments() async => documents;

  @override
  Future<List<AccessPolicy>> getAccessPolicies(String cid) async {
    return accessPolicies[cid] ?? const [];
  }

  @override
  Future<void> grantAccess(String cid, String peerDid) async {
    final policies = [...accessPolicies[cid] ?? const <AccessPolicy>[]];
    if (!policies.any((p) => p.peerDid == peerDid)) {
      policies.add(
        AccessPolicy(cid: cid, peerDid: peerDid, grantedAt: DateTime.now()),
      );
    }
    accessPolicies[cid] = policies;
  }

  @override
  Future<void> revokeAccess(String cid, String peerDid) async {
    accessPolicies[cid] = (accessPolicies[cid] ?? const [])
        .where((p) => p.peerDid != peerDid)
        .toList();
  }

  @override
  Future<List<AuditLog>> getRecentAuditLogs(int limit) async => auditLogs;

  @override
  Future<PorChallenge> issueChallenge(String cid, String peerId) async {
    final challenge = PorChallenge(
      challengeId: 'challenge-${issuedChallenges.length + 1}',
      cid: cid,
      peerId: peerId,
      issuedAt: DateTime.now(),
    );
    issuedChallenges = [...issuedChallenges, challenge];
    return challenge;
  }

  @override
  Future<bool> verifyChallenge(PorChallenge challenge) async => verifyResult;
}
