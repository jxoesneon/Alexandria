import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  int _sidebarTab = 0; // 0: TOC, 1: Editions & Formats, 2: Safe Harbor & Legal, 3: Annotations
  final Map<int, GlobalKey> _headingKeys = {};
  bool _isSyncingScroll = false;

  final TextEditingController _editionSearchController = TextEditingController();
  String _editionSearchQuery = '';
  String _editionFilterFormat = 'all';

  void _openEditionsPanel() {
    ref.read(sidebarVisibleProvider.notifier).state = true;
    setState(() {
      _sidebarTab = 1;
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _editionSearchController.dispose();
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
              width: 380,
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
        // Scalable Edition Indicator & Side Panel Opener (ALX-001 §3 & Anti-Slop)
        versionsAsync.when(
          data: (versions) {
            if (versions.isEmpty) return const SizedBox.shrink();
            final currentActive = activeCid ??
                (versions.any((v) => v.format == 'md-unabridged')
                    ? versions.firstWhere((v) => v.format == 'md-unabridged').cid
                    : versions.first.cid);
            final activeVersion = versions.firstWhere(
              (v) => v.cid == currentActive,
              orElse: () => versions.first,
            );
            final isBrief = activeVersion.format == 'md-brief';
            final editionLabel = isBrief ? 'Executive Brief' : 'Full Unabridged';
            final accentColor = isBrief ? Colors.lightBlueAccent : Colors.amber;

            return Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Edition: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: _openEditionsPanel,
                    borderRadius: BorderRadius.circular(6),
                    hoverColor: accentColor.withValues(alpha: 0.1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.5),
                          width: 1.0,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isBrief ? Icons.flash_on : Icons.article,
                            size: 14,
                            color: accentColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            editionLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '(${_formatSize(activeVersion.sizeBytes)})',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${versions.length} available',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 18),
                    tooltip: 'Open Editions Catalog (${versions.length} versions)',
                    visualDensity: VisualDensity.compact,
                    onPressed: _openEditionsPanel,
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

      case _BlockType.math:
        return _buildMathDisplayBlock(context, block.text, zoom);

      case _BlockType.image:
        return _buildImageFigureBlock(context, block, zoom);

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

  Widget _buildMathDisplayBlock(BuildContext context, String tex, double zoom) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF14171F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.cyanAccent.withValues(alpha: 0.3),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              tex,
              mathStyle: MathStyle.display,
              textStyle: TextStyle(
                fontSize: 18 * zoom,
                color: const Color(0xFFE2E8F0),
              ),
              onErrorFallback: (err) => SelectableText(
                tex,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14 * zoom,
                  color: Colors.cyanAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'FORMULA • KaTeX',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: tex));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('LaTeX equation copied to clipboard'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, size: 11, color: Colors.grey),
                      SizedBox(width: 4),
                      Text('Copy LaTeX',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageFigureBlock(
      BuildContext context, _MarkdownBlock block, double zoom) {
    final url = block.imageUrl ?? '';
    final alt = block.imageAlt ?? block.text;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20.0),
      alignment: Alignment.center,
      child: InkWell(
        onTap: () => _openImageLightbox(context, url, alt),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                constraints: const BoxConstraints(
                  maxHeight: 520,
                  maxWidth: 820,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF14171F),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                child: _resolveImageWidget(context, url, alt),
              ),
            ),
            if (alt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Figure: $alt',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 12 * zoom,
                        color: Colors.grey[400],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInlineImageBadge(
      BuildContext context, String url, String alt, double zoom) {
    return InkWell(
      onTap: () => _openImageLightbox(context, url, alt),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image, size: 12, color: Colors.cyanAccent),
            const SizedBox(width: 4),
            Text(
              alt.isNotEmpty ? alt : 'Image',
              style: TextStyle(
                fontSize: 12 * zoom,
                color: Colors.cyanAccent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolveImageWidget(BuildContext context, String url, String alt) {
    // 1. SVG
    if (url.toLowerCase().endsWith('.svg') ||
        url.startsWith('data:image/svg+xml')) {
      if (url.startsWith('data:image/svg+xml;base64,')) {
        final base64String =
            url.substring('data:image/svg+xml;base64,'.length);
        final decoded = utf8.decode(base64Decode(base64String));
        return SvgPicture.string(decoded, fit: BoxFit.contain);
      } else if (url.startsWith('data:image/svg+xml;utf8,') ||
          url.startsWith('data:image/svg+xml,')) {
        final prefix = url.startsWith('data:image/svg+xml;utf8,')
            ? 'data:image/svg+xml;utf8,'
            : 'data:image/svg+xml,';
        final svgString = Uri.decodeComponent(url.substring(prefix.length));
        return SvgPicture.string(svgString, fit: BoxFit.contain);
      } else if (url.startsWith('http://') || url.startsWith('https://')) {
        return SvgPicture.network(
          url,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      } else if (url.startsWith('assets/')) {
        return SvgPicture.asset(url, fit: BoxFit.contain);
      } else {
        return SvgPicture.file(File(url), fit: BoxFit.contain);
      }
    }

    // 2. Base64 Raster Image
    if (url.startsWith('data:image/') && url.contains(';base64,')) {
      final parts = url.split(';base64,');
      if (parts.length == 2) {
        try {
          final bytes = base64Decode(parts[1]);
          return Image.memory(bytes, fit: BoxFit.contain);
        } catch (_) {
          return _buildImageErrorWidget(context, url, alt);
        }
      }
    }

    // 3. IPFS URI / CID
    String effectiveUrl = url;
    if (url.startsWith('ipfs://')) {
      final cid = url.substring('ipfs://'.length);
      effectiveUrl = 'https://ipfs.io/ipfs/$cid';
    } else if (url.startsWith('/ipfs/')) {
      final cid = url.substring('/ipfs/'.length);
      effectiveUrl = 'https://ipfs.io/ipfs/$cid';
    } else if (url.startsWith('bafy') || url.startsWith('Qm')) {
      effectiveUrl = 'https://ipfs.io/ipfs/$url';
    }

    // 4. Remote HTTP/HTTPS
    if (effectiveUrl.startsWith('http://') ||
        effectiveUrl.startsWith('https://')) {
      return Image.network(
        effectiveUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final percent = progress.expectedTotalBytes != null
              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
              : null;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                    value: percent,
                    strokeWidth: 2,
                  ),
                  const SizedBox(height: 8),
                  const Text('Loading visual asset...',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildImageErrorWidget(context, url, alt);
        },
      );
    }

    // 5. Local File
    if (File(url).existsSync()) {
      return Image.file(
        File(url),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageErrorWidget(context, url, alt);
        },
      );
    }

    // 6. Asset Image
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildImageErrorWidget(context, url, alt);
        },
      );
    }

    // Fallback: graceful placeholder card
    return _buildImageErrorWidget(context, url, alt);
  }

  Widget _buildImageErrorWidget(BuildContext context, String url, String alt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      color: Colors.black26,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 36, color: Colors.amber),
          const SizedBox(height: 8),
          Text(
            alt.isNotEmpty ? alt : 'Archival Visual Asset',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          SelectableText(
            url,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'AIR-GAPPED OR OFFLINE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.copy, size: 12),
                label:
                    const Text('Copy Asset URI', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Asset URI copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openImageLightbox(BuildContext context, String url, String alt) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF0F1117),
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 750),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.image, size: 18, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alt.isNotEmpty ? alt : 'Visual Artifact Inspection',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    tooltip: 'Copy Image Reference',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Image reference copied to clipboard')),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(
                child: Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: _resolveImageWidget(context, url, alt),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Pinch or scroll to zoom • Click and drag to pan • Air-gapped peer preservation',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      ),
    );
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

    final spans = _parseInlineFormatting(context, text, baseStyle, zoom);
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.left,
    );
  }

  List<InlineSpan> _parseInlineFormatting(
      BuildContext context, String text, TextStyle baseStyle, double zoom) {
    final spans = <InlineSpan>[];
    final regex = RegExp(
        r'(\*\*.*?\*\*|\*.*?\*|`.*?`|!\[.*?\]\(.*?\)|\$\$.*?\$\$|\$[^\$\n]+\$)');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: baseStyle,
        ));
      }

      final matchText = match.group(0)!;
      if (matchText.startsWith('**') &&
          matchText.endsWith('**') &&
          matchText.length >= 4) {
        spans.add(TextSpan(
          text: matchText.substring(2, matchText.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (matchText.startsWith('*') &&
          matchText.endsWith('*') &&
          matchText.length >= 2) {
        spans.add(TextSpan(
          text: matchText.substring(1, matchText.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (matchText.startsWith('`') &&
          matchText.endsWith('`') &&
          matchText.length >= 2) {
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
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 13 * zoom),
            ),
          ),
        ));
      } else if (matchText.startsWith('![') && matchText.endsWith(')')) {
        final imgMatch =
            RegExp(r'^!\[(.*?)\]\((.*?)\)$').firstMatch(matchText);
        if (imgMatch != null) {
          final alt = imgMatch.group(1) ?? '';
          var url = imgMatch.group(2) ?? '';
          if (url.contains(' "')) url = url.split(' "').first.trim();
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _buildInlineImageBadge(context, url, alt, zoom),
          ));
        }
      } else if (matchText.startsWith(r'$$') &&
          matchText.endsWith(r'$$') &&
          matchText.length >= 4) {
        final mathStr = matchText.substring(2, matchText.length - 2).trim();
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border:
                  Border.all(color: Colors.cyanAccent.withValues(alpha: 0.2)),
            ),
            child: Math.tex(
              mathStr,
              mathStyle: MathStyle.display,
              textStyle: TextStyle(
                fontSize: 16 * zoom,
                color: const Color(0xFFE2E8F0),
              ),
              onErrorFallback: (err) => Text(
                mathStr,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.cyanAccent,
                  fontSize: 14 * zoom,
                ),
              ),
            ),
          ),
        ));
      } else if (matchText.startsWith(r'$') &&
          matchText.endsWith(r'$') &&
          matchText.length >= 2) {
        final mathStr = matchText.substring(1, matchText.length - 1).trim();
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Math.tex(
              mathStr,
              mathStyle: MathStyle.text,
              textStyle: TextStyle(
                fontSize: 16 * zoom,
                color: const Color(0xFFE2E8F0),
              ),
              onErrorFallback: (err) => Text(
                mathStr,
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: Colors.cyanAccent,
                  fontSize: 13 * zoom,
                ),
              ),
            ),
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

      // 1. Fenced Code Block
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

      // 2. Display Math Formula Block ($$...$$)
      if (trimmed.startsWith(r'$$')) {
        if (trimmed.endsWith(r'$$') && trimmed.length > 4) {
          blocks.add(_MarkdownBlock(
            type: _BlockType.math,
            text: trimmed.substring(2, trimmed.length - 2).trim(),
          ));
          i++;
          continue;
        } else {
          final mathLines = <String>[];
          final firstLine = trimmed.substring(2).trim();
          if (firstLine.isNotEmpty) mathLines.add(firstLine);
          i++;
          while (i < lines.length && !lines[i].trim().endsWith(r'$$')) {
            mathLines.add(lines[i]);
            i++;
          }
          if (i < lines.length) {
            final lastLine = lines[i].trim();
            final lastContent =
                lastLine.substring(0, lastLine.length - 2).trim();
            if (lastContent.isNotEmpty) mathLines.add(lastContent);
            i++;
          }
          blocks.add(_MarkdownBlock(
            type: _BlockType.math,
            text: mathLines.join('\n').trim(),
          ));
          continue;
        }
      }

      // 3. Standalone Image Block (![alt](url))
      // Use manual string extraction instead of regex to correctly handle
      // long base64 data URIs that contain parentheses inside the URL.
      if (trimmed.startsWith('![') &&
          trimmed.contains('](') &&
          trimmed.endsWith(')')) {
        final altEnd = trimmed.indexOf('](');
        if (altEnd != -1) {
          final alt = trimmed.substring(2, altEnd);
          // URL is everything between `](` and the final `)`
          var url = trimmed.substring(altEnd + 2, trimmed.length - 1);
          if (url.contains(' "')) {
            url = url.split(' "').first.trim();
          }
          blocks.add(_MarkdownBlock(
            type: _BlockType.image,
            text: alt,
            imageUrl: url.trim(),
            imageAlt: alt.trim(),
          ));
          i++;
          continue;
        }
      }

      // 4. Horizontal Rule / Divider
      if (trimmed == '---' || trimmed == '***') {
        blocks.add(const _MarkdownBlock(type: _BlockType.divider, text: ''));
        i++;
        continue;
      }

      // 5. Headings
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

      // 6. Blockquote
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

      // 7. List item
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

      // 8. Default paragraph: aggregate multi-line paragraph
      final paragraphLines = <String>[line];
      i++;
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !lines[i].trim().startsWith('#') &&
          !lines[i].trim().startsWith('```') &&
          !lines[i].trim().startsWith(r'$$') &&
          !lines[i].trim().startsWith('![') &&
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
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.toc, size: 13),
                label: Text('TOC', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.layers_outlined, size: 13),
                label: Text('Editions', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              ButtonSegment(
                value: 2,
                icon: Icon(Icons.shield_outlined, size: 13),
                label: Text('Legal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              ButtonSegment(
                value: 3,
                icon: Icon(Icons.note_alt_outlined, size: 13),
                label: Text('Notes', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
              ),
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
                  ? _buildEditionsView(context)
                  : _sidebarTab == 2
                      ? _buildSafeHarborView(context)
                      : _buildAnnotationsView(context),
        ),
      ],
    );
  }

  Widget _buildEditionsView(BuildContext context) {
    final versionsAsync =
        ref.watch(documentVersionsProvider(widget.documentCid));
    final activeCid = ref.watch(activeVersionCidProvider(widget.documentCid));

    return versionsAsync.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(height: 12),
            Text('Loading Merkle manifestations...',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Error querying versions: $err',
              style: const TextStyle(color: Colors.redAccent)),
        ),
      ),
      data: (versions) {
        final currentActive = activeCid ??
            (versions.any((v) => v.format == 'md-unabridged')
                ? versions.firstWhere((v) => v.format == 'md-unabridged').cid
                : (versions.isNotEmpty ? versions.first.cid : widget.documentCid));

        // Filter by search query
        var filtered = versions.where((v) {
          final q = _editionSearchQuery.trim().toLowerCase();
          if (q.isEmpty) return true;
          final isBrief = v.format == 'md-brief';
          final name =
              isBrief ? 'executive brief' : 'full unabridged primary text';
          return name.contains(q) ||
              v.format.toLowerCase().contains(q) ||
              v.cid.toLowerCase().contains(q);
        }).toList();

        // Filter by category chip
        if (_editionFilterFormat == 'unabridged') {
          filtered = filtered.where((v) => v.format == 'md-unabridged').toList();
        } else if (_editionFilterFormat == 'brief') {
          filtered = filtered.where((v) => v.format == 'md-brief').toList();
        } else if (_editionFilterFormat == 'other') {
          filtered = filtered
              .where((v) =>
                  v.format != 'md-unabridged' && v.format != 'md-brief')
              .toList();
        }

        final totalBytes = versions.fold<int>(0, (sum, v) => sum + v.sizeBytes);
        final countUnabridged =
            versions.where((v) => v.format == 'md-unabridged').length;
        final countBrief = versions.where((v) => v.format == 'md-brief').length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header / Overview
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.layers_outlined,
                                size: 16, color: Colors.amber),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Editions & Formats',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${versions.length} versions',
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Content-addressed manifestations (ALX-001 §3). Immutable CIDs pinned to P2P mesh.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: TextField(
                controller: _editionSearchController,
                decoration: InputDecoration(
                  hintText: 'Search format, name, CID...',
                  hintStyle: const TextStyle(fontSize: 12),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: _editionSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _editionSearchController.clear();
                            setState(() => _editionSearchQuery = '');
                          },
                        )
                      : null,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: const TextStyle(fontSize: 12),
                onChanged: (val) {
                  setState(() => _editionSearchQuery = val);
                },
              ),
            ),

            // Filter Chips
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChoiceChip(
                      label: 'All (${versions.length})',
                      selected: _editionFilterFormat == 'all',
                      onSelected: () =>
                          setState(() => _editionFilterFormat = 'all'),
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChoiceChip(
                      label: 'Unabridged ($countUnabridged)',
                      selected: _editionFilterFormat == 'unabridged',
                      onSelected: () =>
                          setState(() => _editionFilterFormat = 'unabridged'),
                    ),
                    const SizedBox(width: 6),
                    _buildFilterChoiceChip(
                      label: 'Briefs ($countBrief)',
                      selected: _editionFilterFormat == 'brief',
                      onSelected: () =>
                          setState(() => _editionFilterFormat = 'brief'),
                    ),
                  ],
                ),
              ),
            ),

            // Results count bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'Showing ${filtered.length} of ${versions.length} editions',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${_formatSize(totalBytes)} on mesh',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Virtualized List (Handles thousands of editions efficiently)
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.filter_list_off,
                              size: 36, color: Colors.grey),
                          const SizedBox(height: 8),
                          Text(
                            'No editions match "$_editionSearchQuery"',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              _editionSearchController.clear();
                              setState(() {
                                _editionSearchQuery = '';
                                _editionFilterFormat = 'all';
                              });
                            },
                            child: const Text('Clear Filters',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12.0),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final v = filtered[index];
                        final isCurrent = v.cid == currentActive;
                        return _buildEditionCard(context, v,
                            isCurrent: isCurrent);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChoiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor.withValues(alpha: 0.3),
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : Theme.of(context).textTheme.bodySmall?.color,
          ),
        ),
      ),
    );
  }

  Widget _buildEditionCard(BuildContext context, ContentVersion v,
      {required bool isCurrent}) {
    final isBrief = v.format == 'md-brief';
    final editionTitle = isBrief
        ? 'Executive Brief'
        : (v.format == 'md-unabridged'
            ? 'Full Unabridged Primary Text'
            : v.format.toUpperCase());
    final accentColor = isBrief ? Colors.lightBlueAccent : Colors.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isCurrent
            ? accentColor.withValues(alpha: 0.12)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrent
              ? accentColor.withValues(alpha: 0.6)
              : Theme.of(context).dividerColor.withValues(alpha: 0.4),
          width: isCurrent ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (!isCurrent) {
            ref
                .read(activeVersionCidProvider(widget.documentCid).notifier)
                .state = v.cid;
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(0);
            }
            ref.read(readerProgressProvider.notifier).state = 0.0;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Switched to $editionTitle (${v.format})'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Icon + Title + Active Badge + Size
              Row(
                children: [
                  Icon(
                    isBrief ? Icons.flash_on : Icons.article,
                    size: 16,
                    color: accentColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      editionTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: isCurrent
                            ? accentColor
                            : Theme.of(context).textTheme.titleSmall?.color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isCurrent) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.5)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check,
                              size: 10, color: Colors.greenAccent),
                          SizedBox(width: 3),
                          Text(
                            'ACTIVE',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.greenAccent,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _formatSize(v.sizeBytes),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Format badge and Swarm indicator
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      v.format.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.sensors,
                      size: 12, color: Colors.greenAccent),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Text(
                      '4 Seed Peers • Verified Merkle Root',
                      style: TextStyle(fontSize: 10, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // CID Multihash display with Copy button
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tag, size: 12, color: Colors.cyanAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        v.cid,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Colors.cyanAccent,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: v.cid));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('CID copied to clipboard'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(2.0),
                        child:
                            Icon(Icons.copy, size: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),

              // Switch action if not current
              if (!isCurrent) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                    ),
                    icon: const Icon(Icons.swap_horiz, size: 14),
                    label: const Text('Switch to this Edition',
                        style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      ref
                          .read(activeVersionCidProvider(widget.documentCid)
                              .notifier)
                          .state = v.cid;
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                      ref.read(readerProgressProvider.notifier).state = 0.0;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Switched to $editionTitle (${v.format})'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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

enum _BlockType { h1, h2, h3, divider, quote, code, math, image, listItem, paragraph }

class _MarkdownBlock {
  final _BlockType type;
  final String text;
  final GlobalKey? key;
  final String? listPrefix;
  final String? imageUrl;
  final String? imageAlt;

  const _MarkdownBlock({
    required this.type,
    required this.text,
    this.key,
    this.listPrefix,
    this.imageUrl,
    this.imageAlt,
  });
}
