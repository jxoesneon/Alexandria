import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/content_repository.dart';
import '../../models/workspace_models.dart';
import '../../providers/workspace_providers.dart';

class MetadataEditorScreen extends ConsumerStatefulWidget {
  const MetadataEditorScreen({super.key});

  @override
  ConsumerState<MetadataEditorScreen> createState() =>
      _MetadataEditorScreenState();
}

class _MetadataEditorScreenState extends ConsumerState<MetadataEditorScreen> {
  String? _selectedNoteId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notesAsync = ref.watch(notesListProvider);

    return notesAsync.when(
      data: (notes) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 800;
            String? selectedId = _selectedNoteId;
            if (isWide && selectedId == null && notes.isNotEmpty) {
              selectedId = notes.first.id;
            }

            Widget body;
            if (isWide) {
              body = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 280,
                    child: _buildNoteList(notes, selectedId, theme),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: selectedId == null
                        ? const Center(child: Text('Select a note'))
                        : _buildEditorPane(selectedId, theme),
                  ),
                ],
              );
            } else if (selectedId != null) {
              body = _buildEditorPane(selectedId, theme);
            } else {
              body = _buildNoteList(notes, null, theme);
            }

            return Scaffold(
              appBar: AppBar(
                title: const Text('Metadata Editor'),
                elevation: 0,
                scrolledUnderElevation: 0,
                automaticallyImplyLeading: false,
                leading: !isWide && _selectedNoteId != null
                    ? IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back to notes',
                        onPressed: () => setState(() => _selectedNoteId = null),
                      )
                    : null,
              ),
              body: body,
            );
          },
        );
      },
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (err, stack) => Scaffold(
        body: Center(
          child: Text(
            'Error loading notes: $err',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ),
    );
  }

  Widget _buildNoteList(List<Note> notes, String? selectedId, ThemeData theme) {
    if (notes.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            right: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: const Center(child: Text('No notes yet.')),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Notes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];
                final isSelected = note.id == selectedId;
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    selected: isSelected,
                    selectedTileColor: theme.colorScheme.secondaryContainer
                        .withValues(alpha: 0.5),
                    title: Text(
                      note.title,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      '${note.author} • ${note.status.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    onTap: () => setState(() => _selectedNoteId = note.id),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorPane(String selectedId, ThemeData theme) {
    final noteAsync = ref.watch(noteProvider(selectedId));
    return noteAsync.when(
      data: (note) => _EditorPane(key: ValueKey<String>(note.id), note: note),
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (err, stack) => Center(
        child: Text(
          'Error loading note: $err',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    );
  }
}

class _EditorPane extends ConsumerStatefulWidget {
  final Note note;

  const _EditorPane({super.key, required this.note});

  @override
  ConsumerState<_EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends ConsumerState<_EditorPane>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _titleController;
  late final TextEditingController _authorController;
  late final TextEditingController _summaryController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagController;
  late List<String> _tags;
  late NoteStatus _status;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(text: note.title);
    _authorController = TextEditingController(text: note.author);
    _summaryController = TextEditingController(text: note.summary);
    _contentController = TextEditingController(text: note.content);
    _tagController = TextEditingController();
    _tags = List<String>.from(note.tags);
    _status = note.status;
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _summaryController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme),
          const SizedBox(height: 16),
          _buildTextField('Title', _titleController, theme),
          const SizedBox(height: 16),
          _buildTextField('Author', _authorController, theme),
          const SizedBox(height: 16),
          _buildTagsField(theme),
          const SizedBox(height: 16),
          _buildTextField('Summary', _summaryController, theme, maxLines: 3),
          const SizedBox(height: 24),
          TabBar(
            controller: _tabController,
            tabs: const [Tab(text: 'Editor'), Tab(text: 'Preview')],
          ),
          SizedBox(
            height: 360,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBarView(
                controller: _tabController,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _contentController,
                      decoration: const InputDecoration(
                        hintText: 'Enter markdown...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      minLines: 12,
                      keyboardType: TextInputType.multiline,
                      onChanged: (_) =>
                          setState(() => _status = NoteStatus.modified),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildPreview(_contentController.text, theme),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        Text(
          'Note Details',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildStatusChip(theme),
            FilledButton.tonal(
              onPressed: () async {
                await _save();
              },
              child: const Text('Save'),
            ),
            OutlinedButton(
              onPressed: () async {
                await _commit();
              },
              child: const Text('Commit'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final Color statusColor;
    switch (_status) {
      case NoteStatus.draft:
        statusColor = theme.colorScheme.outline;
        break;
      case NoteStatus.saved:
        statusColor = theme.colorScheme.primary;
        break;
      case NoteStatus.modified:
        statusColor = theme.colorScheme.tertiary;
        break;
      case NoteStatus.committed:
        statusColor = theme.colorScheme.secondary;
        break;
    }
    return Chip(
      side: BorderSide(color: statusColor),
      backgroundColor: statusColor.withValues(alpha: 0.15),
      label: Text(
        _status.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: statusColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    ThemeData theme, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      onChanged: (_) => setState(() => _status = NoteStatus.modified),
    );
  }

  Widget _buildTagsField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tags', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _tags
              .map(
                (tag) => InputChip(
                  label: Text(tag),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  deleteIconColor: theme.colorScheme.onPrimaryContainer,
                  onDeleted: () {
                    setState(() {
                      _tags.remove(tag);
                      _status = NoteStatus.modified;
                    });
                  },
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tagController,
          decoration: InputDecoration(
            hintText: 'Add a tag',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                _addTag(_tagController.text);
              },
            ),
          ),
          onSubmitted: (value) {
            _addTag(value);
          },
        ),
      ],
    );
  }

  void _addTag(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _tags.contains(trimmed)) {
      return;
    }
    setState(() {
      _tags.add(trimmed);
      _status = NoteStatus.modified;
      _tagController.clear();
    });
  }

  Future<void> _save() async {
    final updatedNote = widget.note.copyWith(
      title: _titleController.text,
      author: _authorController.text,
      tags: List<String>.from(_tags),
      summary: _summaryController.text,
      content: _contentController.text,
      status: NoteStatus.saved,
    );
    await ref.read(contentRepositoryProvider).saveNote(updatedNote);
    if (mounted) {
      setState(() => _status = NoteStatus.saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note saved')),
      );
      ref.invalidate(noteProvider(updatedNote.id));
      ref.invalidate(notesListProvider);
    }
  }

  Future<void> _commit() async {
    final updatedNote = widget.note.copyWith(
      title: _titleController.text,
      author: _authorController.text,
      tags: List<String>.from(_tags),
      summary: _summaryController.text,
      content: _contentController.text,
      status: NoteStatus.saved,
    );
    final hash =
        await ref.read(contentRepositoryProvider).commitNote(updatedNote);
    if (mounted) {
      setState(() => _status = NoteStatus.committed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Committed as $hash')),
      );
      ref.invalidate(noteProvider(updatedNote.id));
      ref.invalidate(notesListProvider);
    }
  }

  Widget _buildPreview(String content, ThemeData theme) {
    final lines = content.split('\n');
    final children = <Widget>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('### ')) {
        final text = trimmed.substring(4);
        children.add(
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (trimmed.startsWith('## ')) {
        final text = trimmed.substring(3);
        children.add(
          Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (trimmed.startsWith('# ')) {
        final text = trimmed.substring(2);
        children.add(
          Text(
            text,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        final text = trimmed.substring(2);
        children.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• ', style: TextStyle(fontSize: 16)),
              Expanded(
                child: Text.rich(
                  TextSpan(children: _parseInline(text, theme)),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        );
      } else if (trimmed.isEmpty) {
        children.add(const SizedBox(height: 8));
      } else {
        children.add(
          Text.rich(
            TextSpan(children: _parseInline(line, theme)),
            style: theme.textTheme.bodyMedium,
          ),
        );
      }
      children.add(const SizedBox(height: 4));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  List<InlineSpan> _parseInline(String text, ThemeData theme) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.*?)\*\*');
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return spans;
  }
}
