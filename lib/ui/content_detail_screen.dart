import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../data/database.dart';
import '../logic/content_repository.dart';
import '../logic/honor_system.dart';
import '../services/preservation_service.dart';
import '../services/sibling_service.dart';
import '../services/ledger_service.dart';
import '../main.dart';
import 'widgets/glass_card.dart';
import 'theme/app_theme.dart';
import 'widgets/info_glass.dart';

final trustScoreProvider = FutureProvider.family<int, String>((ref, cid) async {
  final honor = ref.watch(honorSystemProvider);
  return honor.getTrustScore(cid);
});

final healthStatusProvider = FutureProvider.family<HealthStatus, String>((
  ref,
  cid,
) async {
  final preservation = ref.read(preservationServiceProvider);
  return preservation.checkContentHealth(cid);
});

final versionsProvider = FutureProvider.family<List<ContentVersion>, int>((
  ref,
  manifestId,
) async {
  final db = ref.watch(databaseProvider);
  return db.getVersionsForManifest(manifestId);
});

/// Provider for detecting sibling content
final siblingsProvider = FutureProvider.family<List<ContentSibling>, String>((
  ref,
  title,
) async {
  final siblingService = ref.watch(siblingServiceProvider);
  final repo = ref.read(contentRepositoryProvider);

  // Get all content for comparison
  final allContent = await repo.getContentPage(page: 0, pageSize: 100);
  final candidates = allContent
      .map(
        (m) => {
          'cid': m.id.toString(), // Use manifest ID as identifier
          'title': m.title,
          'format': m.category,
        },
      )
      .toList();

  return siblingService.findSiblings(
    targetTitle: title,
    targetCid: '', // Exclude self
    candidates: candidates,
  );
});

class ContentDetailScreen extends ConsumerStatefulWidget {
  final ContentManifest manifest;

  const ContentDetailScreen({super.key, required this.manifest});

  @override
  ConsumerState<ContentDetailScreen> createState() =>
      _ContentDetailScreenState();
}

class _ContentDetailScreenState extends ConsumerState<ContentDetailScreen> {
  bool _viewRecorded = false;

  ContentManifest get manifest => widget.manifest;

  @override
  void initState() {
    super.initState();
    _recordViewAction();
  }

  Future<void> _recordViewAction() async {
    if (_viewRecorded) return;
    _viewRecorded = true;

    try {
      final ledgerService = ref.read(ledgerServiceProvider);
      // Record that user is endorsing this content by viewing it
      // Use 'endorseContent' as a passive engagement action
      await ledgerService.recordAction(
        action: LedgerActionType.endorseContent,
        contentCid: 'manifest:${manifest.id}',
      );
    } catch (_) {
      // Silently fail - ledger recording is non-critical
    }
  }

  // Helper to parse tags from JSON string
  List<String> _parseTags(String? tagsJson) {
    if (tagsJson == null || tagsJson.isEmpty) return [];
    try {
      final decoded = jsonDecode(tagsJson);
      if (decoded is List) {
        return decoded.cast<String>();
      }
    } catch (_) {}
    return [];
  }

  Widget _buildMetadataSection(BuildContext context, String metadataJson) {
    try {
      final Map<String, dynamic> metadata = jsonDecode(metadataJson);
      if (metadata.isEmpty) return const SizedBox.shrink();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: metadata.entries.map((e) {
          // Prettify key: snake_case to Title Case
          final key = e.key
              .replaceAll('_', ' ')
              .split(' ')
              .map((word) {
                if (word.isEmpty) return '';
                return word[0].toUpperCase() + word.substring(1);
              })
              .join(' ');

          return Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppTheme.primaryColor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  '$key: ${e.value}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          );
        }).toList(),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final versionsAsync = ref.watch(versionsProvider(manifest.id));
    final tags = _parseTags(manifest.tags);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(manifest.title.toUpperCase()),
        backgroundColor: Colors.transparent,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.primaryColor.withValues(alpha: 0.2),
              AppTheme.canvasColor,
            ],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 100),
            // Header Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GlassCard(
                height: 200,
                child: Row(
                  children: [
                    Container(
                      width: 120,
                      height: 160,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.book,
                        size: 60,
                        color: AppTheme.primaryColor,
                      ),
                    ).animate().shimmer(),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            manifest.title,
                            style: Theme.of(context).textTheme.displayMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "By ${manifest.author ?? 'Unknown'}",
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: AppTheme.primaryColor),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            children: [
                              // Category Chip
                              Chip(
                                label: Text(manifest.category.toUpperCase()),
                                backgroundColor: AppTheme.honorColor.withValues(
                                  alpha: 0.2,
                                ),
                                labelStyle: const TextStyle(
                                  color: AppTheme.honorColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                                padding: EdgeInsets.zero,
                                side: BorderSide.none,
                              ),
                              // Tags
                              ...tags.map(
                                (t) => Chip(
                                  label: Text(t),
                                  backgroundColor: AppTheme.primaryColor
                                      .withValues(alpha: 0.1),
                                  labelStyle: const TextStyle(
                                    color: AppTheme.primaryColor,
                                    fontSize: 10,
                                  ),
                                  side: BorderSide.none,
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Metadata Display
                          if (manifest.metadata != null &&
                              manifest.metadata!.isNotEmpty)
                            _buildMetadataSection(context, manifest.metadata!),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().slideY(begin: 0.2, end: 0, duration: 600.ms).fadeIn(),

            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
                children: [
                  versionsAsync.when(
                    data: (versions) => Row(
                      children: [
                        Text(
                          'VERSIONS (${versions.length})',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(letterSpacing: 2),
                        ),
                        const SizedBox(width: 8),
                        const InfoGlass(
                          title: 'Immutable History',
                          description:
                              'Each version is cryptographically frozen. Pinned versions are verified by the "Health" signal. "Verified" badges indicate Community Trust.',
                          small: true,
                          color: AppTheme.primaryColor,
                        ),
                      ],
                    ),
                    loading: () => const Text('VERSIONS (...)'),
                    error: (_, s) => const Text('VERSIONS (error)'),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _addVersionMock(context, ref),
                    icon: const Icon(
                      Icons.add_circle,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: versionsAsync.when(
                data: (versions) => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: versions.length,
                  itemBuilder: (context, index) {
                    final v = versions[index];
                    final scoreAsync = ref.watch(trustScoreProvider(v.cid));

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: GlassCard(
                        height: 100,
                        onTap: () => _showActionDialog(context, ref, v.cid),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceColor.withValues(
                                  alpha: 0.5,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.file_present,
                                color: Colors.white70,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  v.format.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  v.language,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Health Status Indicator
                            _buildHealthIndicator(ref, v.cid),
                            const SizedBox(width: 8),
                            // Trust Score Badge
                            scoreAsync.when(
                              data: (score) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: score >= 0
                                      ? AppTheme.honorColor.withValues(
                                          alpha: 0.2,
                                        )
                                      : AppTheme.dangerColor.withValues(
                                          alpha: 0.2,
                                        ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: score >= 0
                                        ? AppTheme.honorColor
                                        : AppTheme.dangerColor,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.verified,
                                      size: 16,
                                      color: score >= 0
                                          ? AppTheme.honorColor
                                          : AppTheme.dangerColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '$score',
                                      style: TextStyle(
                                        color: score >= 0
                                            ? AppTheme.honorColor
                                            : AppTheme.dangerColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              loading: () => const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              error: (_, s) =>
                                  const Icon(Icons.error, color: Colors.red),
                            ),
                          ],
                        ),
                      ).animate().slideX(delay: (index * 100).ms).fadeIn(),
                    );
                  },
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showActionDialog(BuildContext context, WidgetRef ref, String cid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor.withValues(alpha: 0.9),
        title: Text(
          'Verify Content',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        content: const Text(
          'Is this content safe, high quality, and correctly labeled?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref
                  .read(honorSystemProvider)
                  .validateContent(
                    targetCid: cid,
                    score: -1,
                    validatorId: 'me',
                  );
              ref.invalidate(trustScoreProvider(cid));
              Navigator.pop(ctx);
            },
            child: const Text(
              'Report (-1)',
              style: TextStyle(color: AppTheme.dangerColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.honorColor,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              ref
                  .read(honorSystemProvider)
                  .validateContent(targetCid: cid, score: 1, validatorId: 'me');
              ref.invalidate(trustScoreProvider(cid));
              Navigator.pop(ctx);
            },
            child: const Text('Verify (+1)'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _downloadContent(context, ref, cid);
            },
            icon: const Icon(Icons.download, color: AppTheme.primaryColor),
            label: const Text(
              'Download & Decrypt',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _healContent(context, ref, cid);
            },
            icon: const Icon(Icons.healing, color: Colors.green),
            label: const Text(
              'Rescue (Re-pin)',
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadContent(
    BuildContext context,
    WidgetRef ref,
    String cid,
  ) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Downloading...')));
      }

      final repo = ref.read(contentRepositoryProvider);
      // Pass the manifest key if it exists
      final data = await repo.downloadContent(
        cid,
        keyBase64: manifest.encryptionKey,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Success! Decrypted ${data.length} bytes.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _healContent(
    BuildContext context,
    WidgetRef ref,
    String cid,
  ) async {
    try {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Healing content...')));
      }

      final preservation = ref.read(preservationServiceProvider);
      final success = await preservation.healContent(cid);

      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Content rescued! You are now a provider.'),
            ),
          );
          ref.invalidate(healthStatusProvider(cid));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not heal content.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addVersionMock(BuildContext context, WidgetRef ref) async {
    try {
      final repo = ref.read(contentRepositoryProvider);
      await repo.addVersion(manifest.uuid, '/path/to/mock', 'en', 'mp4');
      ref.invalidate(versionsProvider(manifest.id));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Version Added!')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _buildHealthIndicator(WidgetRef ref, String cid) {
    final healthAsync = ref.watch(healthStatusProvider(cid));

    return healthAsync.when(
      data: (status) {
        Color color;
        IconData icon;
        String tooltip;

        switch (status) {
          case HealthStatus.healthy:
            color = Colors.green;
            icon = Icons.signal_cellular_4_bar;
            tooltip = 'Healthy - Many peers available';
            break;
          case HealthStatus.endangered:
            color = AppTheme.honorColor;
            icon = Icons.signal_cellular_alt_2_bar;
            tooltip = 'Endangered - Few peers';
            break;
          case HealthStatus.lost:
            color = AppTheme.dangerColor;
            icon = Icons.signal_cellular_0_bar;
            tooltip = 'Lost - No peers found';
            break;
          case HealthStatus.unknown:
            color = Colors.grey;
            icon = Icons.signal_cellular_null;
            tooltip = 'Unknown';
        }

        return Tooltip(
          message: tooltip,
          child: Icon(icon, color: color, size: 20),
        );
      },
      loading: () => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      ),
      error: (_, s) =>
          const Icon(Icons.error_outline, color: Colors.grey, size: 16),
    );
  }
}
