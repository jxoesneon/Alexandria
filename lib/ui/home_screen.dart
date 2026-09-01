import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/glass_card.dart';
import 'widgets/info_glass.dart';
import 'codex/search_screen.dart';
import 'scriptorium/creation_wizard.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.green.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle,
                              size: 14, color: Colors.greenAccent),
                          SizedBox(width: 6),
                          Text(
                            'Network Healthy',
                            style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    const Text('32 Documents Synced',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
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
