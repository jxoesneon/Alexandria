import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/security_models.dart';
import '../../providers/security_providers.dart';

class AuditLogsScreen extends ConsumerWidget {
  const AuditLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(auditLogsProvider);
    final challenges = ref.watch(porChallengesProvider);
    final result = ref.watch(porResultProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit Logs'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle(context, 'Recent Audit Logs'),
            const SizedBox(height: 16),
            logsAsync.when(
              data: (logs) => _buildLogsList(context, logs),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Failed to load audit logs: $err'),
              ),
            ),
            const SizedBox(height: 48),
            _buildSectionTitle(context, 'Proof of Retrievability'),
            const SizedBox(height: 16),
            _buildPorSection(context, ref, challenges, result),
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

  Widget _buildLogsList(BuildContext context, List<AuditLog> logs) {
    final theme = Theme.of(context);

    if (logs.isEmpty) {
      return Text(
        'No audit logs available',
        style: theme.textTheme.bodyMedium,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: logs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final log = logs[index];
        final statusColor =
            log.status == 'Success' ? Colors.green : theme.colorScheme.error;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.event,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        log.actor,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      log.status,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimestamp(log.timestamp),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPorSection(
    BuildContext context,
    WidgetRef ref,
    List<PorChallenge> challenges,
    String? result,
  ) {
    final theme = Theme.of(context);
    final cid = ref.watch(porCidProvider);
    final peerId = ref.watch(porPeerIdProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.4),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'CID',
                    hintText: 'Enter content identifier',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    ref.read(porCidProvider.notifier).state = value;
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Peer ID',
                    hintText: 'Enter peer identifier',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    ref.read(porPeerIdProvider.notifier).state = value;
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: cid.isEmpty || peerId.isEmpty
                      ? null
                      : () async {
                          final challenge = await ref
                              .read(porServiceProvider)
                              .issueChallenge(cid, peerId);
                          ref
                              .read(porChallengesProvider.notifier)
                              .update((state) => [...state, challenge]);
                          ref.read(porResultProvider.notifier).state = null;
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Challenge issued')),
                          );
                        },
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Issue challenge'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (result != null) ...[
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.4),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(
                    result.startsWith('Verified')
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    color: result.startsWith('Verified')
                        ? Colors.green
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Text(
          'Pending challenges',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        _buildChallengesList(context, ref, challenges),
      ],
    );
  }

  Widget _buildChallengesList(
    BuildContext context,
    WidgetRef ref,
    List<PorChallenge> challenges,
  ) {
    if (challenges.isEmpty) {
      return Text(
        'No challenges issued',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: challenges.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final challenge = challenges[index];
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
              vertical: 8.0,
            ),
            title: Text(
              challenge.cid,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'Peer: ${challenge.peerId} · Issued: ${_formatTimestamp(challenge.issuedAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            trailing: FilledButton.tonalIcon(
              onPressed: () async {
                final verified = await ref
                    .read(porServiceProvider)
                    .verifyChallenge(challenge);
                ref.read(porResultProvider.notifier).state = verified
                    ? 'Verified: proof is valid for ${challenge.cid}'
                    : 'Verification failed for ${challenge.cid}';
              },
              icon: const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Verify'),
            ),
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.day.toString().padLeft(2, '0')}/${timestamp.month.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}
