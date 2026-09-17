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
final readingProgressProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final storage = ref.read(secureStorageServiceProvider);
  final raw = await storage.read('reading_progress');
  if (raw == null || raw.isEmpty) return const {};
  try {
    // A valid-JSON non-map payload (list, string, …) previously escaped
    // the FormatException catch as a CastError - treat anything that
    // is not a JSON object as absent state. (campaign-2 hardening) and
    // a map with a non-numeric VALUE ({"cid":"abc"}) escaped the same
    // way through `(value as num).toDouble()` - keep only entries whose
    // value is genuinely a number rather than trusting the shape.
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    final progress = <String, double>{};
    for (final e in Map<String, dynamic>.from(decoded).entries) {
      final v = e.value;
      if (v is num) progress[e.key] = v.toDouble();
    }
    return progress;
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

/// Items the user has recently been reading (progress > 0), or featured additions.
final recentItemsProvider = FutureProvider<List<LibraryItem>>((ref) async {
  final items = await _fetchLibraryItems(ref);
  final withProgress =
      items.where((item) => item.progress > 0).take(10).toList();
  if (withProgress.isNotEmpty) {
    return withProgress;
  }
  return items.take(5).toList();
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
    final version = manifestVersions != null && manifestVersions.isNotEmpty
        ? manifestVersions.firstWhere(
            (v) => v.format == 'md-unabridged',
            orElse: () => manifestVersions.first,
          )
        : null;
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
    tags.addAll(_parseManifestTags(manifest.tags));
  }
  return (tags.toList()..sort()).toList();
});

/// Manifest UUID -> parsed tag set, for faceted search filtering.
final manifestTagsProvider =
    FutureProvider<Map<String, Set<String>>>((ref) async {
  final db = ref.read(databaseProvider);
  final manifests = await db.getAllManifests();
  return {
    for (final m in manifests) m.uuid: _parseManifestTags(m.tags),
  };
});

/// Resolves a [ContentManifest] for a version CID or manifest UUID.
final manifestForCidProvider =
    FutureProvider.family<ContentManifest?, String>((ref, cidOrUuid) async {
  final db = ref.read(databaseProvider);
  final versionMap = await db.getVersionByCid(cidOrUuid);
  if (versionMap != null) {
    final manifestId = versionMap['manifestId'] as int?;
    if (manifestId == null) return null;
    final manifests = await db.getAllManifests();
    for (final m in manifests) {
      if (m.id == manifestId) return m;
    }
    return null;
  }
  final manifestMap = await db.getManifestByUuid(cidOrUuid);
  return manifestMap == null ? null : ContentManifest.fromJson(manifestMap);
});

Set<String> _parseManifestTags(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
  } on FormatException {
    // Not JSON - fall through to the comma-separated form.
  }
  return raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toSet();
}

/// All content versions linked to a specific manifest or document CID
final documentVersionsProvider =
    FutureProvider.family<List<ContentVersion>, String>(
        (ref, documentCidOrUuid) async {
  final db = ref.read(databaseProvider);
  int? manifestId;

  final versionMap = await db.getVersionByCid(documentCidOrUuid);
  if (versionMap != null) {
    manifestId = versionMap['manifestId'] as int?;
  } else {
    final manifestMap = await db.getManifestByUuid(documentCidOrUuid);
    if (manifestMap != null) {
      manifestId = manifestMap['id'] as int?;
    }
  }

  if (manifestId == null) return const [];
  return db.getVersionsForManifest(manifestId);
});

/// In-reader selected active version CID (overriding default)
final activeVersionCidProvider =
    StateProvider.family<String?, String>((ref, documentCidOrUuid) => null);

/// Loads a document by CID (or manifest UUID) and decodes its bytes.
final currentDocumentProvider =
    FutureProvider.family<DocumentStream, String>((ref, documentCid) async {
  final db = ref.read(databaseProvider);
  final repository = ref.read(contentRepositoryProvider);
  final activeVersionCid = ref.watch(activeVersionCidProvider(documentCid));

  ContentVersion? version;
  ContentManifest? manifest;

  if (activeVersionCid != null) {
    final versionMap = await db.getVersionByCid(activeVersionCid);
    if (versionMap != null) {
      version = ContentVersion.fromJson(versionMap);
      final manifests = await db.getAllManifests();
      manifest = manifests.cast<ContentManifest?>().firstWhere(
            (m) => m?.id == version!.manifestId,
            orElse: () => null,
          );
    }
  }

  if (version == null || manifest == null) {
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
        if (versions.isNotEmpty) {
          version = versions.firstWhere(
            (v) => v.format == 'md-unabridged',
            orElse: () => versions.first,
          );
        }
      }
    }
  }

  if (manifest == null || version == null) {
    throw ArgumentError('Document not found: $documentCid');
  }

  final bytes = await repository.retrieveContent(version.cid);
  final content = _decodeContent(bytes);

  return DocumentStream(
    title: manifest.title,
    content: content,
    format: version.format,
    cid: version.cid,
    sizeBytes: version.sizeBytes,
  );
});

/// Computed integrity probe for the active edition (Safe Harbor panel, ALX-010).
/// Re-hashes the stored payload against the CID digest and verifies the
/// edition signature - reports only checks that actually ran.
final contentIntegrityProvider =
    FutureProvider.family<ContentIntegrityReport, String>(
        (ref, documentCid) async {
  final repository = ref.read(contentRepositoryProvider);
  final doc = await ref.watch(currentDocumentProvider(documentCid).future);
  return repository.probeContentIntegrity(doc.cid!);
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
final collectionsTreeProvider =
    FutureProvider<List<CollectionNode>>((ref) async {
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

  return collections.where((c) => c.parentId == null).map(buildNode).toList();
});

/// Items belonging to a selected collection.
final collectionItemsProvider =
    FutureProvider.family<List<CollectionItem>, String?>(
        (ref, collectionId) async {
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
