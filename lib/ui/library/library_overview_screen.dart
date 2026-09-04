import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/library_models.dart';
import '../../providers/library_providers.dart';
import '../../services/sync_service.dart';
import 'collections_shelves_screen.dart';
import 'content_viewer_screen.dart';
import 'discovery_search_screen.dart';

class LibraryOverviewScreen extends ConsumerWidget {
  const LibraryOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(libraryDashboardProvider);
    final recentItemsAsync = ref.watch(recentItemsProvider);
    final newArrivalsAsync = ref.watch(newArrivalsProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final (syncColor, syncLabel) = switch (syncStatus) {
      SyncStatus.idle => (colorScheme.secondary, 'Synced'),
      SyncStatus.syncing => (colorScheme.primary, 'Syncing'),
      SyncStatus.offline => (colorScheme.secondary, 'Offline'),
      SyncStatus.error => (colorScheme.error, 'Sync failed'),
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Center(
              child: Text(
                syncLabel,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: syncColor),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Discovery & Search',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DiscoverySearchScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.collections_bookmark_outlined),
            tooltip: 'Collections & Shelves',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CollectionsShelvesScreen(),
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
            _buildSectionTitle(context, 'Statistics Summary'),
            const SizedBox(height: 16),
            statsAsync.when(
              data: (stats) => _buildStatsGrid(context, stats),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Failed to load stats: $err'),
            ),
            const SizedBox(height: 48),
            _buildSectionTitle(context, 'Continue Reading'),
            const SizedBox(height: 16),
            recentItemsAsync.when(
              data: (items) => _buildRecentItemsCarousel(context, items),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Failed to load recent items: $err'),
            ),
            const SizedBox(height: 48),
            _buildSectionTitle(context, 'New Arrivals'),
            const SizedBox(height: 16),
            newArrivalsAsync.when(
              data: (items) => _buildNewArrivalsFeed(context, items),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Text('Failed to load new arrivals: $err'),
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

  Widget _buildStatsGrid(BuildContext context, LibraryStats stats) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            label: 'Total Items',
            value: stats.totalItems.toString(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            context,
            label: 'Total Size',
            value: stats.totalSize,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            context,
            label: 'Network Status',
            value: stats.networkStatus,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentItemsCarousel(
      BuildContext context, List<LibraryItem> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No recent reading. Open a document to continue.'),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final item = items[index];
          return _buildItemCard(context, item, showProgress: true);
        },
      ),
    );
  }

  Widget _buildNewArrivalsFeed(BuildContext context, List<LibraryItem> items) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text('No items in the library yet.'),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 2.0,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildItemCard(context, item, showProgress: false);
      },
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    LibraryItem item, {
    required bool showProgress,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ContentViewerScreen(documentCid: item.cid),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.author,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (showProgress) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: item.progress,
                backgroundColor: colorScheme.surfaceContainerHighest,
                color: colorScheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                '${(item.progress * 100).toInt()}% completed',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
