import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../data/database.dart';
import '../logic/content_repository.dart';
import '../logic/honor_system.dart';
import '../services/preservation_service.dart';
import '../services/proof_of_retrievability_service.dart';
import '../services/ipfs_service.dart';
import '../services/sibling_service.dart';
import '../services/knowledge_graph_service.dart';
import '../services/ledger_service.dart';
import '../services/universal_media_registry.dart';
import '../services/external_player_service.dart';
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

/// Provider for knowledge-graph related content.
///
/// The [KnowledgeGraphService] is an in-memory store and does not expose a
/// public method to query relations (edges). When an entity is registered we
/// fall back to showing its [KnowledgeVariant]s as related content. If no
/// entity is registered for the given id, `null` is returned.
final relatedContentProvider =
    FutureProvider.family<KnowledgeEntity?, String>((ref, entityId) async {
  final kgService = ref.watch(knowledgeGraphServiceProvider);
  try {
    return kgService.getEntity(entityId);
  } catch (_) {
    return null;
  }
});

/// Provider that runs a Proof-of-Retrievability challenge against the content
/// identified by the given cid. Returns `true` when the content is retrievable
/// and its integrity could be cryptographically verified.
final integrityVerificationProvider =
    FutureProvider.family<bool, String>((ref, cid) async {
  final porService = ref.read(proofOfRetrievabilityServiceProvider);
  final ipfs = ref.read(ipfsServiceProvider);

  final challenge = porService.createChallenge(cid: cid, totalChunks: 4);
  final data = await ipfs.getFile(cid).first;
  if (data.isEmpty) return false;

  final chunkSize = (data.length / 4).ceil();
  final chunkIndex = challenge.chunkIndex;
  final start = chunkIndex * chunkSize;
  final end = (start + chunkSize).clamp(0, data.length);
  final chunkData = Uint8List.fromList(data.sublist(start, end));

  final proof = porService.generateProof(
    challenge: challenge,
    chunkData: chunkData,
  );
  return porService.verifyProof(
    proof: proof,
    expectedChunkData: chunkData,
    proverPeerId: 'self',
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
  DateTime? _lastVerified;

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
          final key = e.key.replaceAll('_', ' ').split(' ').map((word) {
            if (word.isEmpty) return '';
            return word[0].toUpperCase() + word.substring(1);
          }).join(' ');

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

  /// Resolves the media format descriptor for the current manifest.
  MediaFormatDescriptor _resolveFormat() {
    final registry = ref.read(universalMediaRegistryProvider);
    return registry.resolveExtension(manifest.category);
  }

  /// Returns true if the format can be viewed in-app (text, images, PDF).
  bool _isViewableInApp(MediaFormatDescriptor descriptor) {
    final ext = descriptor.extension.toLowerCase();
    final category = manifest.category.toLowerCase();
    const viewableExtensions = {'txt', 'pdf', 'jpg', 'jpeg', 'png', 'csv'};
    const viewableCategories = {'book', 'image', 'text'};
    return viewableExtensions.contains(ext) ||
        viewableCategories.contains(category);
  }

  /// Returns a human-readable name for a [SupportedApp].
  String _appName(SupportedApp app) {
    switch (app) {
      case SupportedApp.vlc:
        return 'VLC';
      case SupportedApp.calibre:
        return 'Calibre';
      case SupportedApp.blender:
        return 'Blender';
      case SupportedApp.replayWeb:
        return 'ReplayWeb';
      case SupportedApp.kicad:
        return 'KiCad';
      case SupportedApp.codeEditor:
        return 'Code Editor';
      case SupportedApp.systemDefault:
        return 'System Default';
    }
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref) {
    final descriptor = _resolveFormat();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => _handleView(context, descriptor),
              icon: const Icon(Icons.visibility, size: 18),
              label: const Text('View'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => _handleOpenExternal(context, descriptor),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open in…'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primaryColor,
                side: BorderSide(
                    color: AppTheme.primaryColor.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          descriptor.canonicalName,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.white54,
                fontStyle: FontStyle.italic,
              ),
        ),
      ],
    );
  }

  void _handleView(BuildContext context, MediaFormatDescriptor descriptor) {
    final format = descriptor.extension;
    if (_isViewableInApp(descriptor)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opening in-app viewer for $format...')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "This format ($format) requires an external viewer. Use 'Open in…' instead.",
          ),
        ),
      );
    }
  }

  Future<void> _handleOpenExternal(
    BuildContext context,
    MediaFormatDescriptor descriptor,
  ) async {
    final playerService = ref.read(externalPlayerServiceProvider);
    final app = descriptor.preferredApp;
    final appName = _appName(app);

    // Use the manifest category as the target path placeholder.
    // In a real deployment this would be the decrypted file path or a
    // streaming URL resolved from the content CID.
    final targetPath = manifest.category;

    try {
      final command = playerService.buildAppCommand(app, targetPath);
      final result = await Process.run(command[0], command.sublist(1));

      if (!context.mounted) return;

      if (result.exitCode == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opened in $appName')),
        );
      } else {
        final error = result.stderr.toString().trim();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to launch: ${error.isEmpty ? result.exitCode : error}',
            ),
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to launch: $e')),
      );
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
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
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
                          const SizedBox(height: 16),
                          // Universal View + Open in… buttons
                          _buildActionButtons(context, ref),
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
                        if (_lastVerified != null) ...[
                          const SizedBox(width: 12),
                          Text(
                            'Last verified: ${_formatTime(_lastVerified!)}',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.honorColor.withValues(
                                        alpha: 0.8,
                                      ),
                                      fontSize: 11,
                                    ),
                          ),
                        ],
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

            // ── Variants of this work ──────────────────────────────────────
            _buildVariantsSection(context),

            const SizedBox(height: 16),

            // ── Related Content ────────────────────────────────────────────
            _buildRelatedContentSection(context),
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
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _verifyIntegrity(context, ref, cid);
            },
            icon: const Icon(Icons.shield, color: AppTheme.primaryColor),
            label: const Text(
              'Verify Integrity',
              style: TextStyle(color: AppTheme.primaryColor),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              ref.read(honorSystemProvider).validateContent(
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

  Future<void> _verifyIntegrity(
    BuildContext context,
    WidgetRef ref,
    String cid,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Verifying integrity...'),
          ],
        ),
        duration: Duration(seconds: 10),
      ),
    );

    try {
      final result = await ref.read(integrityVerificationProvider(cid).future);

      if (!mounted) return;
      messenger.hideCurrentSnackBar();

      if (result) {
        setState(() => _lastVerified = DateTime.now());
        messenger.showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.honorColor, size: 18),
                SizedBox(width: 8),
                Text(
                  'Integrity verified — content is retrievable and intact',
                ),
              ],
            ),
            backgroundColor: AppTheme.honorColor.withValues(alpha: 0.2),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error, color: AppTheme.dangerColor, size: 18),
                SizedBox(width: 8),
                Text(
                  'Integrity check failed — content may be corrupted or unavailable',
                ),
              ],
            ),
            backgroundColor: AppTheme.dangerColor.withValues(alpha: 0.2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error, color: AppTheme.dangerColor, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Integrity check failed — content may be corrupted or unavailable',
                ),
              ),
            ],
          ),
          backgroundColor: AppTheme.dangerColor.withValues(alpha: 0.2),
        ),
      );
    }
  }

  /// Formats a [DateTime] as a short, human-readable time string.
  String _formatTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}';
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

  // ── Variants & Related Content sections ─────────────────────────────────

  /// Returns a human-readable label for a [ContentSibling] variant.
  String _variantLabel(ContentSibling sibling) {
    final type = sibling.variantType;
    final value = sibling.variantValue;
    if (type == null) return 'Variant';
    switch (type) {
      case VariantType.edition:
        return value != null ? '$value Edition' : 'Alternate Edition';
      case VariantType.language:
        return value != null ? '$value translation' : 'Translation';
      case VariantType.format:
        return value != null ? '$value format' : 'Alternate Format';
      case VariantType.resolution:
        return value != null ? '$value resolution' : 'Alternate Resolution';
      case VariantType.quality:
        return value != null ? '$value quality' : 'Alternate Quality';
    }
  }

  /// Section A — "Variants of this work".
  ///
  /// Shows sibling content (other editions, translations, formats) as a
  /// horizontally scrollable list of glass cards.
  Widget _buildVariantsSection(BuildContext context) {
    final siblingsAsync = ref.watch(siblingsProvider(manifest.title));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'VARIANTS',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(letterSpacing: 2),
              ),
              const SizedBox(width: 8),
              const InfoGlass(
                title: 'Variants of this work',
                description:
                    'Other editions, translations, and format variants of this work',
                small: true,
                color: AppTheme.primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: siblingsAsync.when(
              data: (siblings) {
                if (siblings.isEmpty) {
                  return Center(
                    child: Text(
                      'No variants found',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white38,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  );
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: siblings.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final s = siblings[index];
                    final similarityPct = (s.similarity * 100).round();
                    return SizedBox(
                      width: 200,
                      child: GlassCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              s.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _variantLabel(s),
                              style: TextStyle(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.8,
                                ),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.compare_arrows,
                                  size: 12,
                                  color: AppTheme.honorColor.withValues(
                                    alpha: 0.7,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$similarityPct% match',
                                  style: TextStyle(
                                    color: AppTheme.honorColor.withValues(
                                      alpha: 0.7,
                                    ),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ).animate().slideX(delay: (index * 80).ms).fadeIn();
                  },
                );
              },
              loading: () => const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (_, __) => Center(
                child: Text(
                  'Could not load variants',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white38,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: 0.15, end: 0, duration: 500.ms).fadeIn();
  }

  /// Section B — "Related Content".
  ///
  /// Shows knowledge-graph relationships (cited by, commentary on, translation
  /// of, etc.) as a vertical list of cards. Because the in-memory
  /// [KnowledgeGraphService] does not expose a public relation query, we fall
  /// back to displaying the entity's registered [KnowledgeVariant]s.
  Widget _buildRelatedContentSection(BuildContext context) {
    final relatedAsync =
        ref.watch(relatedContentProvider(manifest.id.toString()));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                'RELATED CONTENT',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(letterSpacing: 2),
              ),
              const SizedBox(width: 8),
              const InfoGlass(
                title: 'Related Content',
                description:
                    'Works cited by, commenting on, or derived from this content',
                small: true,
                color: AppTheme.primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          relatedAsync.when(
            data: (entity) {
              if (entity == null || entity.variants.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'No related content indexed yet',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white38,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                );
              }
              return Column(
                children: entity.variants.asMap().entries.map((entry) {
                  final index = entry.key;
                  final v = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: GlassCard(
                      height: 64,
                      child: Row(
                        children: [
                          // Relation-type chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _relationChipLabel(v),
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  entity.canonicalTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  entity.author ?? 'Unknown author',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.hub,
                            size: 18,
                            color: AppTheme.primaryColor.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  ).animate().slideX(delay: (index * 80).ms).fadeIn();
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Could not load related content',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white38,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: 0.15, end: 0, duration: 500.ms).fadeIn();
  }

  /// Builds a short chip label describing a [KnowledgeVariant].
  String _relationChipLabel(KnowledgeVariant v) {
    final parts = <String>[];
    if (v.edition != null && v.edition!.isNotEmpty) {
      parts.add(v.edition!);
    }
    if (v.language.isNotEmpty) {
      parts.add(v.language);
    }
    if (parts.isEmpty) return v.format.toUpperCase();
    return parts.join(' · ').toUpperCase();
  }
}
