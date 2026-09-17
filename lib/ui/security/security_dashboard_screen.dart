import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/security_models.dart';
import '../../providers/security_providers.dart';
import '../common/identity_required_cta.dart';
import '../common/alexandria_app_bar.dart';
import '../profile_screen.dart';
import 'access_control_screen.dart';
import 'audit_logs_screen.dart';
import 'key_management_screen.dart';

class SecurityDashboardScreen extends ConsumerWidget {
  const SecurityDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(securityOverviewProvider);
    final alertsAsync = ref.watch(securityAlertsProvider);

    return Scaffold(
      appBar: alexandriaAppBar(
        title: 'Security Dashboard',
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Key Management',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const KeyManagementScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.lock_person_outlined),
            tooltip: 'Access Control',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AccessControlScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'Audit Logs',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AuditLogsScreen(),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, 'Security Score'),
            const SizedBox(height: 16),
            overviewAsync.when(
              data: (overview) => _buildScoreCard(context, overview),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Failed to load score: $err'),
              ),
            ),
            const SizedBox(height: 48),
            _buildSectionTitle(context, 'Encryption Status'),
            const SizedBox(height: 16),
            overviewAsync.when(
              data: (overview) => _buildEncryptionCard(
                context,
                overview.encryptionEnabled,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Failed to load status: $err'),
              ),
            ),
            const SizedBox(height: 48),
            _buildSectionTitle(context, 'Recent Alerts'),
            const SizedBox(height: 16),
            alertsAsync.when(
              data: (alerts) => _buildAlertsList(context, alerts),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Failed to load alerts: $err'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
    );
  }

  Widget _buildScoreCard(BuildContext context, SecurityOverview overview) {
    final theme = Theme.of(context);
    final badgeColor = _scoreColor(overview.score);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Overall Score',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    overview.score.toString(),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                border: Border.all(
                  color: badgeColor.withValues(alpha: 0.5),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _scoreLabel(overview.score),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEncryptionCard(BuildContext context, bool enabled) {
    final theme = Theme.of(context);
    final icon = enabled ? Icons.lock_outlined : Icons.lock_open_outlined;
    final statusColor = enabled ? Colors.green : theme.colorScheme.error;
    final title = enabled ? 'Encryption active' : 'Encryption disabled';
    final subtitle = enabled
        ? 'Files are encrypted locally before storage and sharing.'
        : 'Encryption is currently turned off. Sensitive data may be exposed.';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: statusColor),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsList(BuildContext context, List<SecurityAlert> alerts) {
    if (alerts.isEmpty) {
      return Text(
        'No recent alerts',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: alerts.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final alert = alerts[index];
        final color = _severityColor(alert.severity);
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            leading: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            title: Text(
              alert.message,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
            subtitle: Text(
              '${_formatTimestamp(alert.timestamp)} · ${alert.severity}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            trailing: _remediationFor(context, alert),
          ),
        );
      },
    );
  }

  /// Remediation action for alert types that have a real destination.
  /// Informational alerts get no action.
  Widget? _remediationFor(BuildContext context, SecurityAlert alert) {
    final message = alert.message.toLowerCase();
    if (message.startsWith('no identity configured')) {
      return TextButton(
        onPressed: () => showDialog(
          context: context,
          builder: (context) => const AlertDialog(
            content: IdentityRequiredCta.noIdentity(),
          ),
        ),
        child: const Text('Create identity'),
      );
    }
    if (message.startsWith('backup your identity')) {
      return TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProfileScreen()),
        ),
        child: const Text('Back up'),
      );
    }
    if (message.startsWith('recent access denials')) {
      return TextButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AuditLogsScreen()),
        ),
        child: const Text('View logs'),
      );
    }
    return null;
  }

  Color _scoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _scoreLabel(int score) {
    if (score >= 80) return 'Secure';
    if (score >= 50) return 'Fair';
    return 'At risk';
  }

  Color _severityColor(String severity) {
    return switch (severity.toLowerCase()) {
      'high' => Colors.red,
      'medium' => Colors.orange,
      _ => Colors.green,
    };
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
