import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/library_models.dart';
import '../../providers/library_providers.dart';

class CollectionsShelvesScreen extends ConsumerWidget {
  const CollectionsShelvesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Collections & Shelves'),
        actions: const [
          _CollectionManagementToolbar(),
        ],
      ),
      body: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Collection Tree View
          SizedBox(
            width: 250,
            child: _CollectionTreeView(),
          ),
          VerticalDivider(width: 1),
          // Right: Drag-and-drop Item Grid (Main Area)
          Expanded(
            child: _ItemGrid(),
          ),
        ],
      ),
    );
  }
}

class _CollectionManagementToolbar extends ConsumerWidget {
  const _CollectionManagementToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.create_new_folder_outlined),
          tooltip: 'Create Collection',
          onPressed: () {
            // Action to create collection
          },
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: 'Share Collection',
          onPressed: () {
            // Action to share collection
          },
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete Collection',
          onPressed: () {
            // Action to delete collection
          },
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

class _CollectionTreeView extends ConsumerWidget {
  const _CollectionTreeView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(collectionsTreeProvider);
    final selectedId = ref.watch(selectedCollectionIdProvider);

    return treeAsync.when(
      data: (tree) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children:
            tree.map((node) => _buildNode(node, ref, selectedId, 0)).toList(),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
    );
  }

  Widget _buildNode(
      CollectionNode node, WidgetRef ref, String? selectedId, int depth) {
    final isSelected = node.id == selectedId;

    if (node.children.isEmpty) {
      return ListTile(
        contentPadding:
            EdgeInsets.only(left: 16.0 + (depth * 16.0), right: 16.0),
        title: Text(node.name),
        selected: isSelected,
        leading: const Icon(Icons.folder_outlined),
        onTap: () {
          ref.read(selectedCollectionIdProvider.notifier).state = node.id;
        },
      );
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.only(left: 16.0 + (depth * 16.0), right: 16.0),
      title: Text(node.name),
      leading: const Icon(Icons.folder_outlined),
      initiallyExpanded: true,
      children: node.children
          .map((child) => _buildNode(child, ref, selectedId, depth + 1))
          .toList(),
    );
  }
}

class _ItemGrid extends ConsumerWidget {
  const _ItemGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedCollectionIdProvider);

    if (selectedId == null) {
      return const Center(
        child: Text('Select a collection to view its contents.'),
      );
    }

    final itemsAsync = ref.watch(collectionItemsProvider(selectedId));

    return itemsAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return const Center(
            child: Text('This collection is empty.'),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 0.75,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return _DraggableItemCard(item: item);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
    );
  }
}

class _DraggableItemCard extends StatelessWidget {
  final CollectionItem item;

  const _DraggableItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<CollectionItem>(
      data: item,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 150,
          height: 200,
          child: _ItemCardContent(item: item),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.5,
        child: _ItemCardContent(item: item),
      ),
      child: _ItemCardContent(item: item),
    );
  }
}

class _ItemCardContent extends StatelessWidget {
  final CollectionItem item;

  const _ItemCardContent({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Center(
                child: Icon(Icons.menu_book_outlined,
                    size: 48, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              item.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.format,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
