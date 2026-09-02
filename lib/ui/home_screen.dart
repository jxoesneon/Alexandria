import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/preservation_service.dart';
import '../services/ipfs_service.dart';
import 'widgets/glass_card.dart';
import 'widgets/info_glass.dart';
import 'codex/search_screen.dart';
import 'scriptorium/creation_wizard.dart';

/// Summary of preservation health across all pinned content.
class PreservationHealthSummary {
  final int healthy;
  final int endangered;
  final int lost;
  final int total;

  const PreservationHealthSummary({
    required this.healthy,
    required this.endangered,
    required this.lost,
    required this.total,
  });

  bool get allHealthy => endangered == 0 && lost == 0 && total > 0;
}

/// Checks the health of every pinned CID and returns an aggregated summary.
final preservationHealthProvider =
    FutureProvider.autoDispose<PreservationHealthSummary>((ref) async {
  final ipfs = ref.watch(ipfsServiceProvider);
  final preservation = ref.watch(preservationServiceProvider);
  final cids = ipfs.pinnedCids.toList();

  if (cids.isEmpty) {
    return const PreservationHealthSummary(
        healthy: 0, endangered: 0, lost: 0, total: 0);
  }

  int healthy = 0;
  int endangered = 0;
  int lost = 0;

  for (final cid in cids) {
    final status = await preservation.checkContentHealth(cid);
    switch (status) {
      case HealthStatus.healthy:
        healthy++;
        break;
      case HealthStatus.endangered:
        endangered++;
        break;
      case HealthStatus.lost:
        lost++;
        break;
      case HealthStatus.unknown:
        // Treat unknown as endangered so it surfaces to the user.
        endangered++;
        break;
    }
  }

  return PreservationHealthSummary(
    healthy: healthy,
    endangered: endangered,
    lost: lost,
    total: cids.length,
  );
});

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final healthAsync = ref.watch(preservationHealthProvider);
    final pinnedCount = ref.watch(ipfsServiceProvider).pinnedCids.length;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.auto_stories, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            const Text('Alexandria',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search Library',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SearchScreen()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        children: [
          // Friendly Hero Status Card
          GlassCard(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    healthAsync.when(
                      data: (summary) => _buildHealthBadge(summary),
                      loading: () => _buildLoadingBadge(),
                      error: (e, _) => _buildErrorBadge(),
                    ),
                    const Spacer(),
                    Text('$pinnedCount Documents Synced',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Your Decentralized Library',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'All saved books, research papers, and media are safely stored locally and backed up across the peer-to-peer network.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const CreationWizard()),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add to Library'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Preservation Health Card
          healthAsync.when(
            data: (summary) => _buildPreservationHealthCard(theme, summary),
            loading: () => GlassCard(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Checking preservation health…',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            error: (e, _) => GlassCard(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Could not check preservation health.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(preservationHealthProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Quick Overview Stats
          const Row(
            children: [
              Expanded(
                child: InfoGlass(
                  title: 'Storage Used',
                  value: '428 MB',
                  icon: Icons.pie_chart_outline,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: InfoGlass(
                  title: 'Connected Peers',
                  value: '18 Active',
                  icon: Icons.hub_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recent Documents Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Additions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SearchScreen()),
                  );
                },
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Document Item Card
          _buildDocumentCard(
            context,
            title: 'Tractatus Logico-Philosophicus',
            author: 'Ludwig Wittgenstein',
            category: 'Philosophy',
            format: 'PDF',
            size: '4.2 MB',
            isEncrypted: true,
          ),
          const SizedBox(height: 10),
          _buildDocumentCard(
            context,
            title: 'Principles of Quantum Mechanics',
            author: 'Paul Dirac',
            category: 'Physics',
            format: 'DJVU',
            size: '12.8 MB',
            isEncrypted: false,
          ),
          const SizedBox(height: 10),
          _buildDocumentCard(
            context,
            title: 'Global Climate Dataset 2026',
            author: 'Open Earth Initiative',
            category: 'Dataset',
            format: 'PARQUET',
            size: '45.1 MB',
            isEncrypted: false,
          ),
        ],
      ),
    );
  }

  Widget _buildHealthBadge(PreservationHealthSummary summary) {
    final Color color;
    final IconData icon;
    final String label;

    if (summary.lost > 0) {
      color = Colors.red;
      icon = Icons.error;
      label = '${summary.lost} Content Lost';
    } else if (summary.endangered > 0) {
      color = Colors.amber;
      icon = Icons.warning_amber_rounded;
      label = '${summary.endangered} Content Endangered';
    } else {
      color = Colors.green;
      icon = Icons.check_circle;
      label = 'All Content Healthy';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 6),
          Text(
            'Checking…',
            style: TextStyle(
                color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 14, color: Colors.red),
          SizedBox(width: 6),
          Text(
            'Health Unknown',
            style: TextStyle(
                color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildPreservationHealthCard(
      ThemeData theme, PreservationHealthSummary summary) {
    if (summary.total == 0) {
      return GlassCard(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            Icon(Icons.shield_outlined,
                color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No content preserved yet. Add artifacts to start tracking their health.',
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ),
          ],
        ),
      );
    }

    if (summary.allHealthy) {
      return GlassCard(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            const Icon(Icons.verified, color: Colors.greenAccent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'All artifacts preserved',
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preservation Health',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  'Healthy',
                  summary.healthy.toString(),
                  Colors.green,
                  Icons.check_circle_outline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  'Endangered',
                  summary.endangered.toString(),
                  Colors.amber,
                  Icons.warning_amber_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  'Lost',
                  summary.lost.toString(),
                  Colors.red,
                  Icons.error_outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(
      String label, String count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            count,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(
    BuildContext context, {
    required String title,
    required String author,
    required String category,
    required String format,
    required String size,
    required bool isEncrypted,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(14.0),
      onTap: () {},
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                format,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '$author • $category',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          if (isEncrypted)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.0),
              child: Icon(Icons.lock_outline, size: 16, color: Colors.amber),
            ),
          Text(size, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
        ],
      ),
    );
  }
}
