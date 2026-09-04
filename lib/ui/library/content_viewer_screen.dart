import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_providers.dart';

class ContentViewerScreen extends ConsumerWidget {
  final String documentCid;

  const ContentViewerScreen({
    super.key,
    required this.documentCid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docAsync = ref.watch(currentDocumentProvider(documentCid));
    final showSidebar = ref.watch(sidebarVisibleProvider);
    final useOpenDyslexic = ref.watch(openDyslexicProvider);
    final ttsActive = ref.watch(ttsActiveProvider);
    final zoomLevel = ref.watch(zoomLevelProvider);
    final progress = ref.watch(readerProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Content Viewer',
            style: TextStyle(fontWeight: FontWeight.w500)),
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
                      : 'Text-to-Speech activated.'),
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
              if (zoomLevel > 0.5) {
                ref.read(zoomLevelProvider.notifier).state -= 0.1;
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.toc),
            tooltip: 'Toggle Context Panel',
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
                  child: CircularProgressIndicator(strokeWidth: 2)),
              error: (err, stack) =>
                  Center(child: Text('Error loading document: $err')),
              data: (doc) {
                return Center(
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 800),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48.0, vertical: 48.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontFamily:
                                      useOpenDyslexic ? 'OpenDyslexic' : null,
                                  fontSize: 32 * zoomLevel,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 32),
                          Text(
                            doc.content,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                                  fontFamily:
                                      useOpenDyslexic ? 'OpenDyslexic' : null,
                                  fontSize: 18 * zoomLevel,
                                  height: 1.7,
                                  letterSpacing: useOpenDyslexic ? 0.5 : null,
                                ),
                          ),
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
              width: 320,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
                color: Theme.of(context).colorScheme.surface,
              ),
              child: _buildSidebar(context, ref),
            ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Row(
            children: [
              Text(
                'Reading Progress',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Slider(
                  value: progress,
                  onChanged: (val) {
                    ref.read(readerProgressProvider.notifier).state = val;
                  },
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${(progress * 100).toInt()}%',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, WidgetRef ref) {
    final annotationsAsync = ref.watch(annotationsProvider(documentCid));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Context & Annotations',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: annotationsAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (err, stack) => Center(child: Text('Error: $err')),
            data: (annotations) {
              if (annotations.isEmpty) {
                return const Center(
                  child: Text(
                    'No annotations available.',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                itemCount: annotations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: const Icon(Icons.bookmark_outline, size: 20),
                    title: Text(
                      annotations[index].text,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    dense: true,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
