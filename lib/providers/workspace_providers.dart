import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../data/database.dart';
import '../logic/content_repository.dart';
import '../models/workspace_models.dart';
import '../services/fast_cdc_service.dart';
import '../services/metadata_service.dart';

// ---------------------------------------------------------------------------
// Workspace Dashboard
// ---------------------------------------------------------------------------

final activeWorkspacesProvider = StreamProvider<List<Workspace>>((ref) {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.watchAllManifests().map((manifests) {
    return manifests.map((m) {
      return Workspace(
        id: m.uuid,
        name: m.title,
        pendingTasks: _pendingTaskCount(m),
      );
    }).toList();
  });
});

int _pendingTaskCount(ContentManifest m) {
  var count = 0;
  if (m.author == null || m.author!.isEmpty) count++;
  if (m.description == null || m.description!.isEmpty) count++;
  if (m.tags == null || m.tags!.isEmpty) count++;
  return count;
}

final activityFeedProvider = StreamProvider<List<ActivityEvent>>((ref) {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.watchAllManifests().map((manifests) {
    final sorted = [...manifests]
      ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return sorted.take(20).map((m) {
      return ActivityEvent(
        title: m.title,
        description: '${m.category} updated',
        timestamp: m.lastUpdated,
      );
    }).toList();
  });
});

// ---------------------------------------------------------------------------
// Ingestion Pipeline
// ---------------------------------------------------------------------------

final ingestionManagerProvider =
    StateNotifierProvider<IngestionPipelineManager, IngestionState>((ref) {
  return IngestionPipelineManager(ref);
});

final ingestionQueueProvider = StreamProvider<IngestionState>((ref) {
  return ref.watch(ingestionManagerProvider.notifier).stream;
});

class IngestionPipelineManager extends StateNotifier<IngestionState> {
  IngestionPipelineManager(this._ref) : super(const IngestionState());

  final Ref _ref;
  final _uuid = const Uuid();

  /// Per-file ingest ceiling — the same 512 MiB bound
  /// AddContentScreen.maxFileBytes enforces (campaign-2 hardening).
  /// This pipeline reads `file.path` off disk itself, so the picker's
  /// declared size AND the materialized buffer are both checked before
  /// the bytes are chunked or stored; an unbounded `readAsBytes` is a
  /// memory-exhaustion primitive.
  static const int maxIngestBytes = 512 * 1024 * 1024;

  Future<void> addFiles(List<PlatformFile> files) async {
    if (files.isEmpty) return;

    final repo = _ref.read(contentRepositoryProvider);
    final existing = await repo.getAllManifests();

    final pendingItems = files.map((file) {
      return IngestionItem(
        id: _uuid.v4(),
        filename: file.name,
        progress: 0.0,
        status: IngestionStatus.pending,
      );
    }).toList();

    state = state.copyWith(
      queue: [...state.queue, ...pendingItems],
      statusMessage: 'Added ${files.length} file(s) to the queue',
    );

    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      await _processFile(file, existing);
    }
  }

  Future<void> _processFile(
    PlatformFile file,
    List<ContentManifest> existing,
  ) async {
    final metadataService = _ref.read(metadataServiceProvider);
    final fastCdc = _ref.read(fastCdcServiceProvider);
    final repo = _ref.read(contentRepositoryProvider);

    _updateItem(
        file.name,
        (item) => item.copyWith(
              status: IngestionStatus.processing,
              progress: 0.2,
            ));

    try {
      // (campaign-2 hardening) bound the ingest BEFORE the byte buffer
      // is touched — the picker's declared size is checked first so an
      // oversized file is refused even when its bytes were never
      // materialized; _readFileBytes re-checks the actual buffer.
      if (file.size > maxIngestBytes) {
        throw StateError(
          'File exceeds the ${maxIngestBytes ~/ (1024 * 1024)} MiB '
          'ingest limit',
        );
      }
      final bytes = await _readFileBytes(file);
      final fileWithBytes = PlatformFile(
        name: file.name,
        size: bytes.length,
        bytes: bytes,
        path: file.path,
        identifier: file.identifier,
      );

      final extracted = await metadataService.extractMetadata(fileWithBytes);
      _updateItem(file.name, (item) => item.copyWith(progress: 0.4));

      fastCdc.chunk(bytes);
      _updateItem(file.name, (item) => item.copyWith(progress: 0.6));

      final title = p.basenameWithoutExtension(file.name);
      if (existing.any((m) => m.title == title)) {
        _updateItem(
            file.name,
            (item) => item.copyWith(
                  status: IngestionStatus.conflict,
                  progress: 0.0,
                  conflictMessage:
                      'Metadata conflict: A document with this title already exists.',
                ));
        _refreshOverallProgress();
        return;
      }

      final format = extracted['format'] as String? ?? 'bin';
      await repo.createContent(
        title: title,
        description: extracted['summary'] as String?,
        fileData: bytes,
        tags: [if (format != 'unknown') format],
        category: format,
        format: format,
        extraMetadata: extracted,
      );

      _updateItem(
          file.name,
          (item) => item.copyWith(
                status: IngestionStatus.completed,
                progress: 1.0,
              ));
    } catch (e, stack) {
      debugPrint('Ingestion failed for ${file.name}: $e\n$stack');
      _updateItem(
          file.name,
          (item) => item.copyWith(
                status: IngestionStatus.error,
                progress: 0.0,
                conflictMessage: 'Ingestion error: $e',
              ));
    }
    _refreshOverallProgress();
  }

  Future<Uint8List> _readFileBytes(PlatformFile file) async {
    Uint8List bytes;
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      bytes = Uint8List.fromList(file.bytes!);
    } else if (file.path != null && file.path!.isNotEmpty) {
      bytes = await File(file.path!).readAsBytes();
    } else {
      // (campaign-2 hardening) previously returned an empty buffer,
      // which ingested a phantom zero-byte manifest and reported the
      // item "completed" — fail loudly instead.
      throw StateError('No file data available (bytes not read)');
    }
    if (bytes.length > maxIngestBytes) {
      throw StateError(
        'File exceeds the ${maxIngestBytes ~/ (1024 * 1024)} MiB '
        'ingest limit',
      );
    }
    return bytes;
  }

  void _updateItem(
      String filename, IngestionItem Function(IngestionItem old) update) {
    final updatedQueue = state.queue.map((item) {
      if (item.filename == filename) {
        return update(item);
      }
      return item;
    }).toList();
    state = state.copyWith(queue: updatedQueue);
  }

  void _refreshOverallProgress() {
    if (state.queue.isEmpty) {
      state = state.copyWith(overallProgress: 0.0);
      return;
    }
    final total =
        state.queue.fold<double>(0, (sum, item) => sum + item.progress);
    final overall = total / state.queue.length;
    final completed =
        state.queue.where((i) => i.status == IngestionStatus.completed).length;
    final message = '$completed of ${state.queue.length} item(s) completed';
    state = state.copyWith(overallProgress: overall, statusMessage: message);
  }
}

// ---------------------------------------------------------------------------
// Metadata Editor
// ---------------------------------------------------------------------------

final notesListProvider = FutureProvider<List<Note>>((ref) async {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.getAllNotes();
});

final noteProvider = FutureProvider.family<Note, String>((ref, id) async {
  final repo = ref.watch(contentRepositoryProvider);
  return repo.getNoteByUuid(id);
});

// ---------------------------------------------------------------------------
// Annotations & Notes
// ---------------------------------------------------------------------------

final annotationsProvider =
    StreamProvider.family<List<Annotation>, String>((ref, docId) {
  if (docId.isEmpty) return Stream.value([]);
  final repo = ref.watch(contentRepositoryProvider);
  return repo.watchAnnotations(docId);
});
