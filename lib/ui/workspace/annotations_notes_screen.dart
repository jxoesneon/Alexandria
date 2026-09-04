import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../logic/content_repository.dart';
import '../../models/workspace_models.dart';
import '../../providers/workspace_providers.dart';

class AnnotationsNotesScreen extends ConsumerStatefulWidget {
  final String docId;

  const AnnotationsNotesScreen({
    super.key,
    this.docId = '',
  });

  @override
  ConsumerState<AnnotationsNotesScreen> createState() =>
      _AnnotationsNotesScreenState();
}

class _AnnotationsNotesScreenState
    extends ConsumerState<AnnotationsNotesScreen> {
  final TextEditingController _newNoteController = TextEditingController();

  @override
  void dispose() {
    _newNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final annotationsAsync = ref.watch(annotationsProvider(widget.docId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Annotations & Notes'),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;
          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildDocumentPreview(widget.docId, theme),
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  flex: 2,
                  child: _buildAnnotationsPanel(annotationsAsync, theme),
                ),
              ],
            );
          }

          return Column(
            children: [
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildDocumentPreview(widget.docId, theme),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                flex: 3,
                child: _buildAnnotationsPanel(annotationsAsync, theme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDocumentPreview(String docId, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Document preview placeholder',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              docId.isEmpty ? 'No document selected' : docId,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnotationsPanel(
      AsyncValue<List<Annotation>> annotationsAsync, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Annotations',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: annotationsAsync.when(
              data: (annotations) {
                if (annotations.isEmpty) {
                  return Center(
                    child: Text(
                      'No annotations yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: annotations.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final annotation = annotations[index];
                    return _buildAnnotationCard(annotation, theme);
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
          const SizedBox(height: 12),
          _buildAddNoteField(theme),
        ],
      ),
    );
  }

  Widget _buildAnnotationCard(Annotation annotation, ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          Icons.comment_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          annotation.text,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: annotation.quote != null
            ? Text(
                '"${annotation.quote}"',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              )
            : null,
        trailing: Text(
          _formatTime(annotation.createdAt),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildAddNoteField(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newNoteController,
                decoration: const InputDecoration(
                  hintText: 'Add a note...',
                  border: InputBorder.none,
                ),
                maxLines: null,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (value) async {
                  await _submitNote(value);
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: 'Add note',
              onPressed: () async {
                await _submitNote(_newNoteController.text);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || widget.docId.isEmpty) {
      return;
    }
    final repo = ref.read(contentRepositoryProvider);
    final annotation = Annotation(
      id: const Uuid().v4(),
      docId: widget.docId,
      text: trimmed,
      createdAt: DateTime.now(),
    );
    await repo.addAnnotation(widget.docId, annotation);
    _newNoteController.clear();
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }
}
