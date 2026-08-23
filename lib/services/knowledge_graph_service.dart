import 'package:flutter_riverpod/flutter_riverpod.dart';

final knowledgeGraphServiceProvider = Provider((ref) => KnowledgeGraphService());

enum VariantResolution {
  vectorPdf,
  ocrClean,
  hd1080p,
  uhd4k,
  rawOriginal,
}

enum KnowledgeRelationType {
  translationOf,
  commentaryOn,
  citedBy,
  editionOf,
  sequelTo,
  derivationOf,
}

class KnowledgeVariant {
  final String cid;
  final String format;
  final String language;
  final String? edition;
  final VariantResolution resolution;
  final int sizeBytes;
  final int peerCount;
  final bool isPinned;
  final int honorTrustScore;

  KnowledgeVariant({
    required this.cid,
    required this.format,
    required this.language,
    this.edition,
    this.resolution = VariantResolution.rawOriginal,
    required this.sizeBytes,
    this.peerCount = 1,
    this.isPinned = false,
    this.honorTrustScore = 10,
  });

  Map<String, dynamic> toJson() => {
    'cid': cid,
    'format': format,
    'language': language,
    'edition': edition,
    'resolution': resolution.name,
    'sizeBytes': sizeBytes,
    'peerCount': peerCount,
    'isPinned': isPinned,
    'honorTrustScore': honorTrustScore,
  };
}

class KnowledgeEntity {
  final String entityId;
  final String canonicalTitle;
  final String? author;
  final String? description;
  final List<String> tags;
  final List<KnowledgeVariant> variants;

  KnowledgeEntity({
    required this.entityId,
    required this.canonicalTitle,
    this.author,
    this.description,
    this.tags = const [],
    this.variants = const [],
  });

  Map<String, dynamic> toJson() => {
    'entityId': entityId,
    'canonicalTitle': canonicalTitle,
    'author': author,
    'description': description,
    'tags': tags,
    'variants': variants.map((v) => v.toJson()).toList(),
  };
}

class KnowledgeEdge {
  final String sourceEntityId;
  final String targetEntityId;
  final KnowledgeRelationType relationType;

  KnowledgeEdge({
    required this.sourceEntityId,
    required this.targetEntityId,
    required this.relationType,
  });
}

class KnowledgeGraphService {
  final Map<String, KnowledgeEntity> _entities = {};
  final List<KnowledgeEdge> _edges = [];

  void registerEntity(KnowledgeEntity entity) {
    _entities[entity.entityId] = entity;
  }

  void addVariant(String entityId, KnowledgeVariant variant) {
    final existing = _entities[entityId];
    if (existing == null) throw ArgumentError('Entity $entityId not found');
    final updatedVariants = List<KnowledgeVariant>.from(existing.variants)..add(variant);
    _entities[entityId] = KnowledgeEntity(
      entityId: existing.entityId,
      canonicalTitle: existing.canonicalTitle,
      author: existing.author,
      description: existing.description,
      tags: existing.tags,
      variants: updatedVariants,
    );
  }

  void addRelation(String sourceId, String targetId, KnowledgeRelationType type) {
    _edges.add(KnowledgeEdge(sourceEntityId: sourceId, targetEntityId: targetId, relationType: type));
  }

  KnowledgeEntity? getEntity(String entityId) => _entities[entityId];

  KnowledgeVariant? selectOptimalVariant(
    String entityId, {
    String? preferredFormat,
    String? preferredLanguage,
  }) {
    final entity = _entities[entityId];
    if (entity == null || entity.variants.isEmpty) return null;

    final candidates = entity.variants.where((v) {
      if (preferredLanguage != null && v.language != preferredLanguage) return false;
      if (preferredFormat != null && v.format.toLowerCase() != preferredFormat.toLowerCase()) return false;
      return true;
    }).toList();

    final pool = candidates.isNotEmpty ? candidates : entity.variants;

    // Score based on health (peerCount), pinning status, and trust score
    pool.sort((a, b) {
      final scoreA = (a.peerCount * 2) + (a.isPinned ? 10 : 0) + (a.honorTrustScore ~/ 5);
      final scoreB = (b.peerCount * 2) + (b.isPinned ? 10 : 0) + (b.honorTrustScore ~/ 5);
      return scoreB.compareTo(scoreA);
    });

    return pool.first;
  }

  List<KnowledgeEntity> searchEntities(String query) {
    final q = query.toLowerCase();
    return _entities.values.where((e) {
      return e.canonicalTitle.toLowerCase().contains(q) ||
          (e.author?.toLowerCase().contains(q) ?? false) ||
          e.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }
}
