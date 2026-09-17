import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../models/library_models.dart';
import '../../providers/library_providers.dart';
import '../content_detail_screen.dart';
import 'content_viewer_screen.dart';

class DiscoverySearchScreen extends ConsumerStatefulWidget {
  const DiscoverySearchScreen({super.key});

  @override
  ConsumerState<DiscoverySearchScreen> createState() =>
      _DiscoverySearchScreenState();
}

class _DiscoverySearchScreenState extends ConsumerState<DiscoverySearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedFormats = {};
  final Set<String> _selectedTags = {};
  String _authorFilter = '';
  bool _isGridView = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SearchResult> _applyFilters(
    List<SearchResult> results,
    Map<String, Set<String>> tagsByManifest,
  ) {
    final authorNeedle = _authorFilter.trim().toLowerCase();
    return results.where((r) {
      if (_selectedFormats.isNotEmpty && !_selectedFormats.contains(r.format)) {
        return false;
      }
      if (_selectedTags.isNotEmpty) {
        final tags = tagsByManifest[r.id] ?? const <String>{};
        if (!_selectedTags.every(tags.contains)) return false;
      }
      if (authorNeedle.isNotEmpty &&
          !r.author.toLowerCase().contains(authorNeedle)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openResult(SearchResult item) async {
    ContentManifest? manifest;
    try {
      manifest = await ref.read(manifestForCidProvider(item.id).future);
    } catch (_) {
      manifest = null;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => manifest == null
            ? ContentViewerScreen(documentCid: item.id)
            : ContentDetailScreen(manifest: manifest),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider(query));
    final tagsByManifest =
        ref.watch(manifestTagsProvider).value ?? const <String, Set<String>>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discovery & Search'),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72.0),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search the decentralized collection...',
              leading: const Padding(
                padding: EdgeInsets.only(left: 8.0),
                child: Icon(Icons.search),
              ),
              trailing: [
                if (query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                    },
                  )
              ],
              onChanged: (value) {
                ref.read(searchQueryProvider.notifier).state = value;
              },
              onSubmitted: (value) {
                ref.read(searchQueryProvider.notifier).state = value;
              },
            ),
          ),
        ),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Faceted Filter Panel (Left)
          SizedBox(
            width: 280,
            child: _buildFilterPanel(
              context,
              ref,
              resultsAsync.valueOrNull ?? const [],
            ),
          ),
          const VerticalDivider(width: 1),

          // Results Area (Center)
          Expanded(
            child: Column(
              children: [
                // Toolbar (List/Grid toggles)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Results',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.grid_view),
                            color: _isGridView
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            onPressed: () => setState(() => _isGridView = true),
                            tooltip: 'Grid View',
                          ),
                          IconButton(
                            icon: const Icon(Icons.view_list),
                            color: !_isGridView
                                ? Theme.of(context).colorScheme.primary
                                : null,
                            onPressed: () =>
                                setState(() => _isGridView = false),
                            tooltip: 'List View',
                          ),
                        ],
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),

                // Results Content
                Expanded(
                  child: resultsAsync.when(
                    data: (results) {
                      final filtered = _applyFilters(results, tagsByManifest);
                      if (filtered.isEmpty) {
                        return const Center(child: Text('No results found.'));
                      }
                      return _isGridView
                          ? _buildGridView(filtered)
                          : _buildListView(filtered);
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, stack) =>
                        Center(child: Text('Error loading results: $err')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(
    BuildContext context,
    WidgetRef ref,
    List<SearchResult> results,
  ) {
    final tagsAsync = ref.watch(availableTagsProvider);
    final formats = results.map((r) => r.format).toSet().toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(24.0),
      children: [
        Text('Filters', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 24),

        // Format Filter
        ExpansionTile(
          title: const Text('Format'),
          initiallyExpanded: true,
          childrenPadding: EdgeInsets.zero,
          tilePadding: EdgeInsets.zero,
          children: formats.isEmpty
              ? [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('No formats in the current results.'),
                  ),
                ]
              : formats
                  .map((format) => CheckboxListTile(
                        title: Text(format),
                        value: _selectedFormats.contains(format),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedFormats.add(format);
                          } else {
                            _selectedFormats.remove(format);
                          }
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ))
                  .toList(),
        ),

        const SizedBox(height: 16),

        // Tags Filter
        ExpansionTile(
          title: const Text('Tags'),
          initiallyExpanded: true,
          childrenPadding: EdgeInsets.zero,
          tilePadding: EdgeInsets.zero,
          children: tagsAsync.when(
            data: (tags) => tags
                .map((tag) => CheckboxListTile(
                      title: Text(tag),
                      value: _selectedTags.contains(tag),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedTags.add(tag);
                        } else {
                          _selectedTags.remove(tag);
                        }
                      }),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ))
                .toList(),
            loading: () => [
              const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator())
            ],
            error: (err, stack) => [Text('Error: $err')],
          ),
        ),

        const SizedBox(height: 16),

        // Author Filter
        ExpansionTile(
          title: const Text('Author'),
          childrenPadding: EdgeInsets.zero,
          tilePadding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Filter by author...',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _authorFilter = value),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGridView(List<SearchResult> results) {
    return GridView.builder(
      padding: const EdgeInsets.all(24.0),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 24.0,
        crossAxisSpacing: 24.0,
        childAspectRatio: 0.75,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final item = results[index];
        return Card(
          elevation: 1,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: InkWell(
            onTap: () => _openResult(item),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Center(
                        child: Icon(
                          item.format == 'PDF'
                              ? Icons.picture_as_pdf
                              : Icons.book,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    item.author,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8.0),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8.0, vertical: 4.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Text(
                        item.format,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListView(List<SearchResult> results) {
    return ListView.separated(
      padding: const EdgeInsets.all(16.0),
      itemCount: results.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          leading: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Icon(
              item.format == 'PDF' ? Icons.picture_as_pdf : Icons.book,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          title:
              Text(item.title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text('${item.author} • ${item.format}'),
          ),
          trailing: Text(
            '${item.dateAdded.year}-${item.dateAdded.month.toString().padLeft(2, '0')}-${item.dateAdded.day.toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => _openResult(item),
        );
      },
    );
  }
}
