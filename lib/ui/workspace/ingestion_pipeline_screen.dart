import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/workspace_models.dart';
import '../../providers/workspace_providers.dart';

class IngestionPipelineScreen extends ConsumerStatefulWidget {
  const IngestionPipelineScreen({super.key});

  @override
  ConsumerState<IngestionPipelineScreen> createState() =>
      _IngestionPipelineScreenState();
}

class _IngestionPipelineScreenState
    extends ConsumerState<IngestionPipelineScreen> {
  IngestionItem? _selectedItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final queueState = ref.watch(ingestionQueueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingestion Pipeline'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Queue Area
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDropzone(theme),
                  const SizedBox(height: 24),
                  Text('Import Queue', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Expanded(
                    child: queueState.when(
                      data: (state) => _buildQueueTable(state, theme),
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Details Pane
          const VerticalDivider(width: 1),
          Expanded(
            flex: 1,
            child: _selectedItem == null
                ? Center(
                    child: Text(
                      'Select an item to view details',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : _buildDetailsPane(_selectedItem!, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildDropzone(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border.all(
          color: theme.colorScheme.outline,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_upload_outlined,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Drag and drop files here',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Supported formats: PDF, EPUB, MD, CSV, Images',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: _browseFiles,
            child: const Text('Browse Files'),
          ),
        ],
      ),
    );
  }

  Future<void> _browseFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result != null && result.files.isNotEmpty && mounted) {
      await ref.read(ingestionManagerProvider.notifier).addFiles(result.files);
    }
  }

  Widget _buildQueueTable(IngestionState state, ThemeData theme) {
    if (state.queue.isEmpty) {
      return const Center(child: Text('Queue is empty.'));
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        itemCount: state.queue.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = state.queue[index];
          final isSelected = _selectedItem?.id == item.id;

          return ListTile(
            selected: isSelected,
            selectedTileColor:
                theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
            leading: _buildStatusIcon(item.status, theme),
            title: Text(item.filename),
            subtitle: item.status == IngestionStatus.processing
                ? LinearProgressIndicator(value: item.progress)
                : Text(item.status.name.toUpperCase(),
                    style: const TextStyle(fontSize: 10)),
            trailing: item.status == IngestionStatus.conflict
                ? IconButton(
                    icon: const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange),
                    onPressed: () => _showConflictDialog(item),
                  )
                : null,
            onTap: () {
              setState(() {
                _selectedItem = item;
              });
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusIcon(IngestionStatus status, ThemeData theme) {
    switch (status) {
      case IngestionStatus.pending:
        return const Icon(Icons.schedule);
      case IngestionStatus.processing:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case IngestionStatus.completed:
        return Icon(Icons.check_circle, color: theme.colorScheme.primary);
      case IngestionStatus.error:
        return Icon(Icons.error, color: theme.colorScheme.error);
      case IngestionStatus.conflict:
        return const Icon(Icons.warning, color: Colors.orange);
    }
  }

  Widget _buildDetailsPane(IngestionItem item, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Item Details', style: theme.textTheme.titleLarge),
          const SizedBox(height: 24),
          _DetailRow(label: 'Filename', value: item.filename),
          const SizedBox(height: 16),
          _DetailRow(label: 'Status', value: item.status.name.toUpperCase()),
          const SizedBox(height: 16),
          _DetailRow(
              label: 'Progress',
              value: '${(item.progress * 100).toStringAsFixed(0)}%'),
          if (item.conflictMessage != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                border: Border.all(color: Colors.orange),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.conflictMessage!,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.orange[800]),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _showConflictDialog(item),
              child: const Text('Resolve Conflict'),
            ),
          ],
        ],
      ),
    );
  }

  void _showConflictDialog(IngestionItem item) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Resolve Conflict'),
          content: Text(
              'How would you like to handle the conflict for ${item.filename}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Overwrite'),
            ),
          ],
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodyLarge,
        ),
      ],
    );
  }
}
