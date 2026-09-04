import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../logic/content_repository.dart';
import '../models/library_models.dart';
import '../services/collection_service.dart' as collection_service;
import '../services/secure_storage_service.dart';
import '../services/sync_service.dart';

/// In-session reader state providers.
final readerProgressProvider = StateProvider<double>((ref) => 0.0);
final sidebarVisibleProvider = StateProvider<bool>((ref) => false);
final openDyslexicProvider = StateProvider<bool>((ref) => false);
final ttsActiveProvider = StateProvider<bool>((ref) => false);
final zoomLevelProvider = StateProvider<double>((ref) => 1.0);

/// Search and collection selection state.
final searchQueryProvider = StateProvider<String>((ref) => '');
final selectedCollectionIdProvider = StateProvider<String?>((ref) => null);

/// Reading progress persisted in secure storage as a JSON map keyed by CID.
final readingProgressProvider = FutureProvider<Map<String, double>>((ref) async {
  final storage = ref.read(secureStorageServiceProvider);
  final raw = await storage.read('reading_progress');
  if (raw == null || raw.isEmpty) return const {};
  try {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map((key, value) => MapEntry(key, (value as num).toDouble()));
  } on FormatException {
    return const {};
  }
});

/// Dashboard statistics derived from the local database and sync status.
final libraryDashboardProvider = FutureProvider<LibraryStats>((ref) async {
  final db = ref.read(databaseProvider);
  final manifests = await db.getAllManifests();
  final versions = await db.select(db.contentVersions).get();
  final totalBytes = versions.fold<int>(0, (sum, v) => sum + v.sizeBytes);
  final syncStatus = ref.watch(syncStatusProvider);
  final networkStatus = switch (syncStatus) {
    SyncStatus.idle => 'Synchronized',
    SyncStatus.syncing => 'Syncing',
    SyncStatus.offline => 'Offline',
    SyncStatus.error => 'Sync failed',
  };

  return LibraryStats(
    totalItems: manifests.length,
    totalSize: _formatBytes(totalBytes),
    networkStatus: networkStatus,
  );
});

/// Items the user has recently been reading (progress > 0).
final recentItemsProvider = FutureProvider<List<LibraryItem>>((ref) async {
  final items = await _fetchLibraryItems(ref);
  return items.where((item) => item.progress > 0).take(10).toList();
});

/// Latest additions to the local library.
final newArrivalsProvider = FutureProvider<List<LibraryItem>>((ref) async {
  final items = await _fetchLibraryItems(ref);
  return items.take(20).toList();
});

/// Fetches manifests from the database and maps them to [LibraryItem] view
/// models, resolving each item's CID from its associated [ContentVersion].
Future<List<LibraryItem>> _fetchLibraryItems(Ref ref) async {
  final db = ref.read(databaseProvider);
  final progressMap = await ref.read(readingProgressProvider.future);
  final manifests = await db.getAllManifests();
  final versions = await db.select(db.contentVersions).get();

  final versionMap = <int, List<ContentVersion>>{};
  for (final version in versions) {
    versionMap.putIfAbsent(version.manifestId, () => []).add(version);
  }

  manifests.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

  return manifests.map((manifest) {
    final manifestVersions = versionMap[manifest.id];
    final version = manifestVersions?.firstOrNull;
    final cid = version?.cid ?? manifest.uuid;
    final progress = progressMap[cid] ?? 0.0;
    return LibraryItem(
      cid: cid,
      title: manifest.title,
      author: manifest.author ?? 'Unknown',
      progress: progress,
    );
  }).toList();
}

/// Search results filtered against the local content manifests.
final searchResultsProvider =
    FutureProvider.family<List<SearchResult>, String>((ref, query) async {
  final db = ref.read(databaseProvider);
  final manifests = await db.getAllManifests();
  final versions = await db.select(db.contentVersions).get();

  final versionMap = <int, List<ContentVersion>>{};
  for (final version in versions) {
    versionMap.putIfAbsent(version.manifestId, () => []).add(version);
  }

  final normalized = query.toLowerCase().trim();
  final results = <SearchResult>[];
  for (final manifest in manifests) {
    final title = manifest.title.toLowerCase();
    final author = (manifest.author ?? '').toLowerCase();
    if (normalized.isNotEmpty &&
        !title.contains(normalized) &&
        !author.contains(normalized)) {
      continue;
    }

    final manifestVersions = versionMap[manifest.id];
    final version = manifestVersions?.firstOrNull;
    final format = version?.format ?? 'bin';
    final dateAdded = version?.createdData ?? manifest.lastUpdated;

    results.add(SearchResult(
      id: manifest.uuid,
      title: manifest.title,
      author: manifest.author ?? 'Unknown',
      format: format.toUpperCase(),
      dateAdded: dateAdded,
    ));
  }

  return results;
});

/// Unique tags extracted from content manifests.
final availableTagsProvider = FutureProvider<List<String>>((ref) async {
  final db = ref.read(databaseProvider);
  final manifests = await db.getAllManifests();
  final tags = <String>{};
  for (final manifest in manifests) {
    final raw = manifest.tags;
    if (raw == null || raw.isEmpty) continue;
    for (final tag in raw.split(',')) {
      final trimmed = tag.trim();
      if (trimmed.isNotEmpty) tags.add(trimmed);
    }
  }
  return (tags.toList()..sort()).toList();
});

/// Loads a document by CID (or manifest UUID) and decodes its bytes.
final currentDocumentProvider =
    FutureProvider.family<DocumentStream, String>((ref, documentCid) async {
  final db = ref.read(databaseProvider);
  final repository = ref.read(contentRepositoryProvider);

  ContentVersion? version;
  ContentManifest? manifest;

  final versionMap = await db.getVersionByCid(documentCid);
  if (versionMap != null) {
    version = ContentVersion.fromJson(versionMap);
    final manifests = await db.getAllManifests();
    manifest = manifests.cast<ContentManifest?>().firstWhere(
          (m) => m?.id == version!.manifestId,
          orElse: () => null,
        );
  } else {
    final manifestMap = await db.getManifestByUuid(documentCid);
    if (manifestMap != null) {
      manifest = ContentManifest.fromJson(manifestMap);
      final versions = await db.getVersionsForManifest(manifest.id);
      version = versions.firstOrNull;
    }
  }

  if (manifest == null || version == null) {
    throw ArgumentError('Document not found: $documentCid');
  }

  final bytes = await repository.retrieveContent(version.cid);
  final content = _decodeContent(bytes);

  return DocumentStream(title: manifest.title, content: content);
});

/// Annotations for a document, derived from collection item notes.
final annotationsProvider =
    FutureProvider.family<List<Annotation>, String>((ref, documentCid) async {
  final service = ref.read(collection_service.collectionServiceProvider);
  final notes = <String>[];
  for (final collection in service.collections) {
    for (final item in collection.items.elements) {
      if (item.contentCid == documentCid && item.note.isNotEmpty) {
        notes.add(item.note);
      }
    }
  }
  return notes.map((note) => Annotation(text: note)).toList();
});

/// Hierarchical tree of collections.
final collectionsTreeProvider = FutureProvider<List<CollectionNode>>((ref) async {
  final service = ref.read(collection_service.collectionServiceProvider);
  final collections = service.collections;

  CollectionNode buildNode(collection_service.Collection collection) {
    final children = collections
        .where((c) => c.parentId == collection.id)
        .map(buildNode)
        .toList();
    return CollectionNode(
      id: collection.id,
      name: collection.name.value,
      children: children,
    );
  }

  return collections
      .where((c) => c.parentId == null)
      .map(buildNode)
      .toList();
});

/// Items belonging to a selected collection.
final collectionItemsProvider =
    FutureProvider.family<List<CollectionItem>, String?>((ref, collectionId) async {
  if (collectionId == null) return const [];

  final service = ref.read(collection_service.collectionServiceProvider);
  final collection = service.getCollection(collectionId);
  if (collection == null) return const [];

  final db = ref.read(databaseProvider);
  final manifests = await db.getAllManifests();
  final versions = await db.select(db.contentVersions).get();

  final manifestById = {for (final m in manifests) m.id: m};
  final versionByCid = {for (final v in versions) v.cid: v};

  final items = <CollectionItem>[];
  for (final item in collection.items.elements) {
    final version = versionByCid[item.contentCid];
    final manifest = version != null ? manifestById[version.manifestId] : null;
    final title = manifest?.title ?? 'Unknown';
    final author = manifest?.author ?? 'Unknown';
    final format = version?.format ?? 'bin';

    items.add(CollectionItem(
      id: item.contentCid,
      title: title,
      author: author,
      format: format.toUpperCase(),
    ));
  }

  return items;
});

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

String _decodeContent(Uint8List bytes) {
  if (bytes.isEmpty) {
    return 'Document content is not available locally.';
  }
  try {
    return utf8.decode(bytes, allowMalformed: true);
  } on FormatException {
    return 'Unable to decode document content.';
  }
}
