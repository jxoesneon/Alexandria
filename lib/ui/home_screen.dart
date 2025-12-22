import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../logic/content_repository.dart';
import '../data/database.dart';
import 'content_detail_screen.dart';
import 'profile_screen.dart';
import 'widgets/glass_card.dart';
import 'theme/app_theme.dart';
import 'widgets/info_glass.dart';

// ... (ContentListNotifier remains same, assume it's imported or I duplicate it if it was top level)
// Actually ContentListNotifier was in home_screen.dart. I should keep it.
// To avoid deleting it, I will use replace_file_content carefully or rewrite the whole file ensuring I include it.

final contentListProvider =
    AsyncNotifierProvider<ContentListNotifier, List<ContentManifest>>(
      ContentListNotifier.new,
    );

class ContentListNotifier extends AsyncNotifier<List<ContentManifest>> {
  int _page = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  static const int _pageSize = 20;

  @override
  Future<List<ContentManifest>> build() async {
    final repo = ref.read(contentRepositoryProvider);
    return await repo.getContentPage(page: 0, pageSize: _pageSize);
  }

  Future<void> fetchMore() async {
    if (state.isLoading || !_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    try {
      final repo = ref.read(contentRepositoryProvider);
      final newItems = await repo.getContentPage(
        page: _page + 1,
        pageSize: _pageSize,
      );
      if (newItems.isEmpty) {
        _hasMore = false;
      } else {
        _page++;
        final currentList = state.value ?? [];
        state = AsyncData([...currentList, ...newItems]);
      }
    } catch (e) {
      // silent fail
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> refresh() async {
    _page = 0;
    _hasMore = true;
    ref.invalidateSelf();
    await future;
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(contentListProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      // AppBar is now Sliver
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppTheme.canvasColor, AppTheme.surfaceColor],
          ),
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 200 &&
                !ref.read(contentListProvider.notifier)._isLoadingMore) {
              ref.read(contentListProvider.notifier).fetchMore();
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              // 1. App Bar
              SliverAppBar(
                title: Text(
                  'THE ATRIUM',
                  style: AppTheme.darkTheme.textTheme.headlineMedium?.copyWith(
                    color: AppTheme.primaryColor,
                    letterSpacing: 2,
                    fontSize: 20,
                  ),
                ),
                centerTitle: true,
                backgroundColor: AppTheme.canvasColor.withValues(alpha: 0.8),
                floating: true,
                snap: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.person_outline, size: 28),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    ),
                  ),
                ],
              ),

              // 2. Featured Section (Endangered)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'ENDANGERED ARCHIVES',
                            style: AppTheme.darkTheme.textTheme.labelMedium
                                ?.copyWith(
                                  color: AppTheme.dangerColor,
                                  letterSpacing: 1.5,
                                ),
                          ),
                          const SizedBox(width: 8),
                          const InfoGlass(
                            title: 'Preservation Alert',
                            description:
                                'These artifacts are hosted by fewer than 3 peers globally. Pin them to your node to save them from permanent deletion.',
                            icon: Icons.warning_amber_rounded,
                            color: AppTheme.dangerColor,
                            small: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: 5,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            return _FeaturedCard(index: index)
                                .animate()
                                .fadeIn(delay: (100 * index).ms)
                                .slideX();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Recent Section Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'FRESH MANIFESTS',
                        style: AppTheme.darkTheme.textTheme.labelMedium
                            ?.copyWith(
                              color: AppTheme.secondaryColor,
                              letterSpacing: 1.5,
                            ),
                      ),
                      const SizedBox(width: 8),
                      const InfoGlass(
                        title: 'The Living Feed',
                        description:
                            'A real-time stream of new knowledge published to the Alexandria network. Every item here is hash-verified.',
                        color: AppTheme.secondaryColor,
                        small: true,
                      ),
                    ],
                  ),
                ),
              ),

              // 4. Infinite List
              contentAsync.when(
                data: (manifests) {
                  if (manifests.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32.0),
                          child: Text('The Library is Empty.'),
                        ),
                      ),
                    );
                  }
                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = manifests[index];
                        final tagsList = _parseTags(item.tags);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16.0),
                          child: _ContentCard(item: item, tagsList: tagsList),
                        ).animate().fadeIn().slideY(begin: 0.1);
                      }, childCount: manifests.length),
                    ),
                  );
                },
                loading: () => const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, trace) =>
                    SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _parseTags(String? tagsJson) {
    if (tagsJson == null || tagsJson.isEmpty) return [];
    try {
      final decoded = jsonDecode(tagsJson);
      if (decoded is List) return decoded.cast<String>();
    } catch (_) {}
    return [];
  }
}

class _FeaturedCard extends StatelessWidget {
  final int index;
  const _FeaturedCard({required this.index});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.dangerColor.withValues(alpha: 0.3)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.surfaceColor, AppTheme.canvasColor],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -20,
            child: Icon(
              Icons.warning_amber_rounded,
              size: 100,
              color: AppTheme.dangerColor.withValues(alpha: 0.05),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CRITICAL • < 3 PEERS',
                    style: TextStyle(
                      color: AppTheme.dangerColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Forbidden Codex #${index + 42}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Help preserve this artifact.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  final ContentManifest item;
  final List<String> tagsList;

  const _ContentCard({required this.item, required this.tagsList});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      height: 140,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ContentDetailScreen(manifest: item)),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.book,
              color: AppTheme.primaryColor,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  item.author ?? 'Unknown Author',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: (tagsList)
                      .take(3)
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.primaryColor.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: Text(
                            t,
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
        ],
      ),
    );
  }
}
