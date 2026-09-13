import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../models/library_models.dart';
import '../../providers/library_providers.dart';

class ContentViewerScreen extends ConsumerStatefulWidget {
  final String documentCid;

  const ContentViewerScreen({
    super.key,
    required this.documentCid,
  });

  @override
  ConsumerState<ContentViewerScreen> createState() =>
      _ContentViewerScreenState();
}

class _ContentViewerScreenState extends ConsumerState<ContentViewerScreen> {
  final ScrollController _scrollController = ScrollController();
  int _sidebarTab = 0; // 0: Contents, 1: Preservation & Safe Harbor, 2: Annotations
  final Map<int, GlobalKey> _headingKeys = {};
  bool _isSyncingScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isSyncingScroll || !_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    if (max <= 0) return;
    final current = (_scrollController.offset / max).clamp(0.0, 1.0);
    if ((current - ref.read(readerProgressProvider)).abs() > 0.02) {
      ref.read(readerProgressProvider.notifier).state = current;
    }
  }

  void _onSliderChanged(double val) {
    ref.read(readerProgressProvider.notifier).state = val;
    if (_scrollController.hasClients) {
      _isSyncingScroll = true;
      final target = val * _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(target);
      _isSyncingScroll = false;
    }
  }

  void _scrollToHeading(GlobalKey key) {
    if (key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(currentDocumentProvider(widget.documentCid));
    final showSidebar = ref.watch(sidebarVisibleProvider);
    final useOpenDyslexic = ref.watch(openDyslexicProvider);
    final ttsActive = ref.watch(ttsActiveProvider);
    final zoomLevel = ref.watch(zoomLevelProvider);
    final progress = ref.watch(readerProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Archival Reader & Content Viewer',
          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
                ttsActive ? Icons.record_voice_over : Icons.voice_over_off),
            tooltip: 'Toggle Text-to-Speech (TTS)',
            onPressed: () {
              ref.read(ttsActiveProvider.notifier).state = !ttsActive;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ttsActive
                      ? 'Text-to-Speech deactivated.'
                      : 'Text-to-Speech active (reading full text).'),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_format),
            tooltip: 'Toggle OpenDyslexic Font',
            onPressed: () {
              ref.read(openDyslexicProvider.notifier).state = !useOpenDyslexic;
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Zoom In',
            onPressed: () {
              ref.read(zoomLevelProvider.notifier).state += 0.1;
            },
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'Zoom Out',
            onPressed: () {
              if (zoomLevel > 0.6) {
                ref.read(zoomLevelProvider.notifier).state -= 0.1;
              }
            },
          ),
          IconButton(
            icon: Icon(showSidebar ? Icons.chrome_reader_mode : Icons.toc),
            tooltip: 'Toggle Reader Context Panel',
            onPressed: () {
              ref.read(sidebarVisibleProvider.notifier).state = !showSidebar;
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: docAsync.when(
              loading: () => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 2),
                    SizedBox(height: 16),
                    Text('Retrieving Merkle DAG blocks from IPFS...'),
                  ],
                ),
              ),
              error: (err, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Text('Error loading document: $err',
                      style: const TextStyle(color: Colors.redAccent)),
                ),
              ),
              data: (doc) {
                final blocks = _parseMarkdownBlocks(doc.content);
                return Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 860),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48.0, vertical: 32.0),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDocumentHeader(context, doc, zoomLevel, useOpenDyslexic),
                          const SizedBox(height: 24),
                          ...blocks.map((block) => _buildBlockWidget(
                                context,
                                block,
                                zoomLevel,
                                useOpenDyslexic,
                              )),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (showSidebar)
            Container(
              width: 340,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: _buildSidebar(context, docAsync.valueOrNull),
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 6.0),
          child: Row(
            children: [
              const Icon(Icons.auto_stories, size: 18, color: Colors.amber),
              const SizedBox(width: 10),
              Text(
                'Reading Progress',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: progress,
                  onChanged: _onSliderChanged,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(progress * 100).toInt()}%',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentHeader(
      BuildContext context, DocumentStream doc, double zoom, bool dyslexic) {
    final versionsAsync = ref.watch(documentVersionsProvider(widget.documentCid));
    final activeCid = doc.cid;
    final isBrief = doc.format == 'md-brief';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isBrief
                    ? Colors.lightBlueAccent.withValues(alpha: 0.15)
                    : Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isBrief
                      ? Colors.lightBlueAccent.withValues(alpha: 0.5)
                      : Colors.amber.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isBrief ? Icons.flash_on : Icons.verified,
                    size: 14,
                    color: isBrief ? Colors.lightBlueAccent : Colors.amber,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isBrief
                        ? 'AUTHENTIC EXECUTIVE BRIEF • 17 U.S.C. § 108'
                        : 'AUTHENTIC UNABRIDGED PRESERVATION RECORD • 17 U.S.C. § 108',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      color: isBrief ? Colors.lightBlueAccent : Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          doc.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontFamily: dyslexic ? 'OpenDyslexic' : null,
                fontSize: 28 * zoom,
                fontWeight: FontWeight.bold,
                height: 1.25,
              ),
        ),
        const SizedBox(height: 12),
        // Multi-version Edition Switcher (Zero catalog duplication)
        versionsAsync.when(
          data: (versions) {
            if (versions.length <= 1) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 2.0, bottom: 8.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Available Editions:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  for (final v in versions)
                    _buildVersionChip(
                      context,
                      v,
                      isSelected: v.cid == (activeCid ?? versions.first.cid),
                    ),
                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 4),
        Divider(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ],
    );
  }

  Widget _buildVersionChip(BuildContext context, ContentVersion v,
      {required bool isSelected}) {
    final isBrief = v.format == 'md-brief';
    final label = isBrief
        ? '⚡ Executive Brief (${_formatSize(v.sizeBytes)})'
        : '📜 Full Unabridged (${_formatSize(v.sizeBytes)})';

    return InkWell(
      onTap: () {
        ref.read(activeVersionCidProvider(widget.documentCid).notifier).state =
            v.cid;
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
        ref.read(readerProgressProvider.notifier).state = 0.0;
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.amber.withValues(alpha: 0.2)
              : Colors.black12,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? Colors.amber
                : Theme.of(context).dividerColor.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 13,
              color: isSelected ? Colors.amber : Colors.grey,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? Colors.amber
                    : Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildBlockWidget(
    BuildContext context,
    _MarkdownBlock block,
    double zoom,
    bool dyslexic,
  ) {
    final theme = Theme.of(context);
    final baseFont = dyslexic ? 'OpenDyslexic' : null;

    switch (block.type) {
      case _BlockType.h1:
        return Padding(
          key: block.key,
          padding: const EdgeInsets.only(top: 32.0, bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                block.text,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFamily: baseFont,
                  fontSize: 24 * zoom,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Container(height: 2, width: 48, color: theme.colorScheme.primary),
            ],
          ),
        );

      case _BlockType.h2:
        return Padding(
          key: block.key,
          padding: const EdgeInsets.only(top: 28.0, bottom: 10.0),
          child: Text(
            block.text,
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: baseFont,
              fontSize: 20 * zoom,
              fontWeight: FontWeight.w700,
              color: Colors.amber[200] ?? Colors.amber,
            ),
          ),
        );

      case _BlockType.h3:
        return Padding(
          key: block.key,
          padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
          child: Text(
            block.text,
            style: theme.textTheme.titleMedium?.copyWith(
              fontFamily: baseFont,
              fontSize: 17 * zoom,
              fontWeight: FontWeight.w600,
            ),
          ),
        );

      case _BlockType.divider:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20.0),
          child: Divider(color: theme.dividerColor.withValues(alpha: 0.4)),
        );

      case _BlockType.quote:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 14.0),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            border: const Border(
              left: BorderSide(color: Colors.amber, width: 3.5),
            ),
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(6),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: _buildRichText(
            context,
            block.text,
            zoom,
            dyslexic,
            isItalic: true,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
          ),
        );

      case _BlockType.code:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 14.0),
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: const Color(0xFF141416),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              block.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14 * zoom,
                color: const Color(0xFFE2E8F0),
                height: 1.4,
              ),
            ),
          ),
        );

      case _BlockType.listItem:
        return Padding(
          padding: const EdgeInsets.only(left: 12.0, bottom: 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                block.listPrefix ?? '• ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16 * zoom,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRichText(
                  context,
                  block.text,
                  zoom,
                  dyslexic,
                ),
              ),
            ],
          ),
        );

      case _BlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14.0),
          child: _buildRichText(
            context,
            block.text,
            zoom,
            dyslexic,
          ),
        );
    }
  }

  Widget _buildRichText(
    BuildContext context,
    String text,
    double zoom,
    bool dyslexic, {
    bool isItalic = false,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodyLarge?.copyWith(
          fontFamily: dyslexic ? 'OpenDyslexic' : null,
          fontSize: 16 * zoom,
          height: 1.75,
          fontStyle: isItalic ? FontStyle.italic : null,
          color: color,
        ) ??
        TextStyle(fontSize: 16 * zoom);

    final spans = _parseInlineFormatting(text, baseStyle);
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.left,
    );
  }

  List<InlineSpan> _parseInlineFormatting(String text, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(\*\*.*?\*\*|\*.*?\*|`.*?`|\$\$.*?\$\$|\$.*?\$)');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      final matchText = match.group(0)!;
      if (matchText.startsWith('**') && matchText.endsWith('**') && matchText.length >= 4) {
        spans.add(TextSpan(
          text: matchText.substring(2, matchText.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (matchText.startsWith('*') && matchText.endsWith('*') && matchText.length >= 2) {
        spans.add(TextSpan(
          text: matchText.substring(1, matchText.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (matchText.startsWith('`') && matchText.endsWith('`') && matchText.length >= 2) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              matchText.substring(1, matchText.length - 1),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ));
      } else if (matchText.startsWith(r'$$') && matchText.endsWith(r'$$')) {
        spans.add(TextSpan(
          text: matchText.substring(2, matchText.length - 2),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            color: Colors.cyanAccent,
            fontWeight: FontWeight.w600,
          ),
        ));
      } else if (matchText.startsWith(r'$') && matchText.endsWith(r'$')) {
        spans.add(TextSpan(
          text: matchText.substring(1, matchText.length - 1),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            color: Colors.cyanAccent[100],
            fontStyle: FontStyle.italic,
          ),
        ));
      } else {
        spans.add(TextSpan(text: matchText, style: baseStyle));
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: baseStyle,
      ));
    }

    return spans;
  }

  List<_MarkdownBlock> _parseMarkdownBlocks(String content) {
    final blocks = <_MarkdownBlock>[];
    final lines = content.split('\n');
    int headingIndex = 0;

    int i = 0;
    while (i < lines.length) {
      final line = lines[i].trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      if (trimmed.startsWith('```')) {
        final codeLines = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // skip closing ```
        blocks.add(_MarkdownBlock(
          type: _BlockType.code,
          text: codeLines.join('\n'),
        ));
        continue;
      }

      if (trimmed == '---' || trimmed == '***') {
        blocks.add(const _MarkdownBlock(type: _BlockType.divider, text: ''));
        i++;
        continue;
      }

      if (trimmed.startsWith('# ')) {
        final key = _headingKeys.putIfAbsent(headingIndex++, () => GlobalKey());
        blocks.add(_MarkdownBlock(
          type: _BlockType.h1,
          text: trimmed.substring(2).trim(),
          key: key,
        ));
        i++;
        continue;
      }

      if (trimmed.startsWith('## ')) {
        final key = _headingKeys.putIfAbsent(headingIndex++, () => GlobalKey());
        blocks.add(_MarkdownBlock(
          type: _BlockType.h2,
          text: trimmed.substring(3).trim(),
          key: key,
        ));
        i++;
        continue;
      }

      if (trimmed.startsWith('### ')) {
        final key = _headingKeys.putIfAbsent(headingIndex++, () => GlobalKey());
        blocks.add(_MarkdownBlock(
          type: _BlockType.h3,
          text: trimmed.substring(4).trim(),
          key: key,
        ));
        i++;
        continue;
      }

      if (trimmed.startsWith('> ')) {
        final quoteLines = <String>[trimmed.substring(2)];
        i++;
        while (i < lines.length && lines[i].trim().startsWith('> ')) {
          quoteLines.add(lines[i].trim().substring(2));
          i++;
        }
        blocks.add(_MarkdownBlock(
          type: _BlockType.quote,
          text: quoteLines.join(' '),
        ));
        continue;
      }

      if (RegExp(r'^(\*|-|\d+\.)\s+').hasMatch(trimmed)) {
        final match = RegExp(r'^(\*|-|\d+\.)\s+').firstMatch(trimmed)!;
        final prefix = match.group(0)!;
        blocks.add(_MarkdownBlock(
          type: _BlockType.listItem,
          text: trimmed.substring(prefix.length),
          listPrefix: prefix,
        ));
        i++;
        continue;
      }

      // Default paragraph: aggregate multi-line paragraph
      final paragraphLines = <String>[line];
      i++;
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !lines[i].trim().startsWith('#') &&
          !lines[i].trim().startsWith('```') &&
          !lines[i].trim().startsWith('> ') &&
          !RegExp(r'^(\*|-|\d+\.)\s+').hasMatch(lines[i].trim()) &&
          lines[i].trim() != '---') {
        paragraphLines.add(lines[i].trim());
        i++;
      }
      blocks.add(_MarkdownBlock(
        type: _BlockType.paragraph,
        text: paragraphLines.join(' '),
      ));
    }

    return blocks;
  }

  Widget _buildSidebar(BuildContext context, DocumentStream? doc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('TOC', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 1, label: Text('Safe Harbor', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 2, label: Text('Notes', style: TextStyle(fontSize: 11))),
            ],
            selected: {_sidebarTab},
            onSelectionChanged: (val) {
              setState(() => _sidebarTab = val.first);
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _sidebarTab == 0
              ? _buildTocView(context, doc)
              : _sidebarTab == 1
                  ? _buildSafeHarborView(context)
                  : _buildAnnotationsView(context),
        ),
      ],
    );
  }

  Widget _buildTocView(BuildContext context, DocumentStream? doc) {
    if (doc == null) {
      return const Center(child: Text('Loading Table of Contents...'));
    }

    final blocks = _parseMarkdownBlocks(doc.content);
    final headings = blocks
        .where((b) =>
            b.type == _BlockType.h1 ||
            b.type == _BlockType.h2 ||
            b.type == _BlockType.h3)
        .toList();

    if (headings.isEmpty) {
      return const Center(child: Text('No section headings found.'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: headings.length,
      itemBuilder: (context, index) {
        final h = headings[index];
        final isH1 = h.type == _BlockType.h1;
        final isH2 = h.type == _BlockType.h2;

        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.only(
            left: isH1 ? 16 : isH2 ? 28 : 40,
            right: 16,
          ),
          leading: Icon(
            isH1
                ? Icons.menu_book
                : isH2
                    ? Icons.subdirectory_arrow_right
                    : Icons.circle,
            size: isH1 ? 16 : isH2 ? 14 : 6,
            color: isH1 ? Colors.amber : Colors.grey,
          ),
          title: Text(
            h.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isH1 ? 13 : 12,
              fontWeight: isH1 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          onTap: () {
            if (h.key != null) {
              _scrollToHeading(h.key!);
            }
          },
        );
      },
    );
  }

  Widget _buildSafeHarborView(BuildContext context) {
    final versionsAsync = ref.watch(documentVersionsProvider(widget.documentCid));
    final activeCid = ref.watch(activeVersionCidProvider(widget.documentCid));

    return ListView(
      padding: const EdgeInsets.all(20.0),
      children: [
        const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.greenAccent, size: 20),
            SizedBox(width: 8),
            Text(
              'Statutory Safe Harbor',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Preserved under 17 U.S.C. § 108 (Library & Archival Reproduction Exemption) and the open public commons. Content is cryptographically pinned to the peer-to-peer decentralized storage mesh with zero tracking or DRM locks.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: 20),
        const Text(
          'Linked Editions & CIDs (Zero Duplication):',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 8),
        versionsAsync.when(
          data: (versions) {
            if (versions.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white10),
                ),
                child: SelectableText(
                  widget.documentCid,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.cyanAccent),
                ),
              );
            }
            final currentActive = activeCid ??
                (versions.any((v) => v.format == 'md-unabridged')
                    ? versions.firstWhere((v) => v.format == 'md-unabridged').cid
                    : versions.first.cid);

            return Column(
              children: versions.map((v) {
                final isCurrent = v.cid == currentActive;
                final isBrief = v.format == 'md-brief';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? (isBrief
                            ? Colors.lightBlueAccent.withValues(alpha: 0.12)
                            : Colors.amber.withValues(alpha: 0.12))
                        : Colors.black26,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCurrent
                          ? (isBrief
                              ? Colors.lightBlueAccent.withValues(alpha: 0.6)
                              : Colors.amber.withValues(alpha: 0.6))
                          : Colors.white10,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isBrief ? Icons.flash_on : Icons.article,
                            size: 14,
                            color:
                                isBrief ? Colors.lightBlueAccent : Colors.amber,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isBrief ? 'Executive Brief' : 'Full Unabridged',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isCurrent
                                  ? (isBrief
                                      ? Colors.lightBlueAccent
                                      : Colors.amber)
                                  : Colors.white70,
                            ),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(width: 6),
                            const Text(
                              '[ACTIVE]',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.greenAccent),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            _formatSize(v.sizeBytes),
                            style:
                                const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        v.cid,
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: Colors.cyanAccent),
                      ),
                      if (!isCurrent) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                            ),
                            icon: const Icon(Icons.swap_horiz, size: 14),
                            label: const Text('Switch Edition',
                                style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              ref
                                  .read(activeVersionCidProvider(widget.documentCid)
                                      .notifier)
                                  .state = v.cid;
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(0);
                              }
                              ref
                                  .read(readerProgressProvider.notifier)
                                  .state = 0.0;
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        _buildMetaRow('Multi-Version Model', '1 Manifest → N CIDs'),
        _buildMetaRow('Catalog Duplication', 'Zero (Deduped by Work UUID)'),
        _buildMetaRow('P2P Redundancy', '4 Seed Peers Active'),
        _buildMetaRow('Integrity Check', 'SHA-256 Merkle-Root OK'),
        _buildMetaRow('Access Mode', 'Air-gapped / Local-First'),
        _buildMetaRow('License', 'Open Access / Commons'),
      ],
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildAnnotationsView(BuildContext context) {
    final annotationsAsync = ref.watch(annotationsProvider(widget.documentCid));
    return annotationsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (annotations) {
        if (annotations.isEmpty) {
          return const Center(
            child: Text('No annotations or reading notes.', style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: annotations.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            return ListTile(
              leading: const Icon(Icons.bookmark_outline, size: 18),
              title: Text(annotations[index].text, style: const TextStyle(fontSize: 13)),
              dense: true,
            );
          },
        );
      },
    );
  }
}

enum _BlockType { h1, h2, h3, divider, quote, code, listItem, paragraph }

class _MarkdownBlock {
  final _BlockType type;
  final String text;
  final GlobalKey? key;
  final String? listPrefix;

  const _MarkdownBlock({
    required this.type,
    required this.text,
    this.key,
    this.listPrefix,
  });
}
