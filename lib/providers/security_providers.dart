import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/security_models.dart';
import '../services/security_overview_service.dart';

final securityOverviewServiceProvider = Provider<SecurityOverviewService>((ref) {
  return SecurityOverviewService(ref);
});

final securityOverviewProvider = FutureProvider<SecurityOverview>((ref) async {
  final service = ref.watch(securityOverviewServiceProvider);
  return service.getOverview();
});

final securityAlertsProvider = StreamProvider<List<SecurityAlert>>((ref) {
  final service = ref.watch(securityOverviewServiceProvider);
  return service.watchSecurityAlerts();
});

// Key management
final keyManagementServiceProvider = Provider<SecurityOverviewService>((ref) {
  return ref.watch(securityOverviewServiceProvider);
});

final didServiceProvider = Provider<SecurityOverviewService>((ref) {
  return ref.watch(securityOverviewServiceProvider);
});

final activeIdentitiesProvider = FutureProvider<List<Keypair>>((ref) {
  final service = ref.watch(keyManagementServiceProvider);
  return service.getActiveIdentities();
});

// Access control
final accessControlServiceProvider = Provider<SecurityOverviewService>((ref) {
  return ref.watch(securityOverviewServiceProvider);
});

final documentsProvider = FutureProvider<List<DocumentOption>>((ref) {
  final service = ref.watch(accessControlServiceProvider);
  return service.getDocuments();
});

final documentAclProvider = FutureProvider.family<List<AccessPolicy>, String>((ref, cid) {
  final service = ref.watch(accessControlServiceProvider);
  return service.getAccessPolicies(cid);
});

final selectedCidProvider = StateProvider<String?>((ref) => null);
final peerDidProvider = StateProvider<String>((ref) => '');

// Audit logs
final auditServiceProvider = Provider<SecurityOverviewService>((ref) {
  return ref.watch(securityOverviewServiceProvider);
});

final auditLogsProvider = FutureProvider<List<AuditLog>>((ref) {
  final service = ref.watch(auditServiceProvider);
  return service.getRecentAuditLogs(20);
});

// Proof of retrievability
final porServiceProvider = Provider<SecurityOverviewService>((ref) {
  return ref.watch(securityOverviewServiceProvider);
});

final porChallengesProvider = StateProvider<List<PorChallenge>>((ref) => const []);
final porCidProvider = StateProvider<String>((ref) => '');
final porPeerIdProvider = StateProvider<String>((ref) => '');
final porResultProvider = StateProvider<String?>((ref) => null);
