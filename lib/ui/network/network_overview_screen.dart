import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/network_models.dart';
import '../../providers/network_providers.dart';
import '../../services/network_overview_service.dart';
import '../common/alexandria_app_bar.dart';
import '../governance_screen.dart';
import 'peer_discovery_screen.dart';
import 'sync_conflict_screen.dart';
import 'transports_config_screen.dart';

class NetworkOverviewScreen extends ConsumerWidget {
  const NetworkOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nodeStatusAsync = ref.watch(nodeStatusProvider);
    final bandwidthAsync = ref.watch(networkTelemetryProvider);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: alexandriaAppBar(
        title: 'Node Operations Dashboard',
        actions: [
          IconButton(
            icon: const Icon(Icons.people_outline),
            tooltip: 'Peer Discovery',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PeerDiscoveryScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_ethernet),
            tooltip: 'Transports',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TransportsConfigScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.sync_alt),
            tooltip: 'Sync & Conflicts',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SyncConflictScreen(),
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
            Text(
              'Network status',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            nodeStatusAsync.when(
              data: (status) => _buildStatusCard(context, ref, status),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Failed to load status: $err'),
            ),
            const SizedBox(height: 32),
            Text(
              'Bandwidth usage',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            bandwidthAsync.when(
              data: (stats) => _buildBandwidthCard(context, stats),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Failed to load telemetry: $err'),
            ),
            const SizedBox(height: 32),
            Text(
              'Governance',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 8.0,
                ),
                leading: const Icon(Icons.how_to_vote_outlined),
                title: const Text('The Parliament'),
                subtitle: const Text(
                  'Protocol proposals, votes, and ratified governance',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GovernanceScreen(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    WidgetRef ref,
    NodeStatus status,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRunning = status.isRunning;
    final statusColor = isRunning ? colorScheme.primary : colorScheme.error;
    final statusLabel = isRunning ? 'Running' : 'Stopped';

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  statusLabel,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  'Peers: ${status.connectedPeers}',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                final service = ref.read(networkOverviewServiceProvider);
                if (isRunning) {
                  await service.stopNode();
                } else {
                  await service.startNode();
                }
              },
              icon: Icon(isRunning ? Icons.stop : Icons.play_arrow),
              label: Text(isRunning ? 'Stop node' : 'Start node'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandwidthCard(BuildContext context, BandwidthStats stats) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildBandwidthMetric(
                    context,
                    label: 'Upload',
                    value: _formatBps(stats.uploadBps),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildBandwidthMetric(
                    context,
                    label: 'Download',
                    value: _formatBps(stats.downloadBps),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  'Bandwidth graph placeholder',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandwidthMetric(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatBps(int bps) {
    if (bps < 1000) {
      return '$bps bps';
    }
    if (bps < 1000000) {
      return '${(bps / 1000).toStringAsFixed(1)} Kbps';
    }
    return '${(bps / 1000000).toStringAsFixed(2)} Mbps';
  }
}
