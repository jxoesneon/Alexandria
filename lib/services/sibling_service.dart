import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider for the SiblingService
final siblingServiceProvider = Provider((ref) => SiblingService());

/// Similarity threshold for sibling detection (Spec §11.5)
const double _similarityThreshold = 0.85;

/// Variant types for content
enum VariantType {
  resolution, // Different resolutions (4K, 1080p, 720p)
  language, // Different languages/translations
  format, // Different file formats (PDF, EPUB, MOBI)
  quality, // Different quality levels (lossless, compressed)
  edition, // Different editions (original, director's cut)
}

/// A detected sibling/variant of content
class ContentSibling {
  final String cid;
  final String title;
  final double similarity;
  final VariantType? variantType;
  final String? variantValue; // e.g., "1080p", "Spanish", "PDF"

  ContentSibling({
    required this.cid,
    required this.title,
    required this.similarity,
    this.variantType,
    this.variantValue,
  });

  Map<String, dynamic> toJson() => {
    'cid': cid,
    'title': title,
    'similarity': similarity,
    'variantType': variantType?.name,
    'variantValue': variantValue,
  };
}

/// Service for detecting and managing content siblings (The Prism)
class SiblingService {
  /// Normalize a title for comparison
  String normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  /// Calculate Levenshtein distance between two strings
  int levenshteinDistance(String s1, String s2) {
    final m = s1.length;
    final n = s2.length;

    // Create matrix
    final d = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    // Initialize first row and column
    for (var i = 0; i <= m; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      d[0][j] = j;
    }

    // Fill matrix
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1, // Deletion
          d[i][j - 1] + 1, // Insertion
          d[i - 1][j - 1] + cost, // Substitution
        ].reduce(min);
      }
    }

    return d[m][n];
  }

  /// Calculate similarity score (0.0 to 1.0)
  double calculateSimilarity(String s1, String s2) {
    final normalized1 = normalizeTitle(s1);
    final normalized2 = normalizeTitle(s2);

    if (normalized1.isEmpty || normalized2.isEmpty) return 0.0;
    if (normalized1 == normalized2) return 1.0;

    final maxLen = max(normalized1.length, normalized2.length);
    final distance = levenshteinDistance(normalized1, normalized2);

    return 1.0 - (distance / maxLen);
  }

  /// Detect if two items are siblings
  bool areSiblings(String title1, String title2) {
    return calculateSimilarity(title1, title2) >= _similarityThreshold;
  }

  /// Detect variant type from metadata differences
  VariantType? detectVariantType({
    String? resolution1,
    String? resolution2,
    String? language1,
    String? language2,
    String? format1,
    String? format2,
  }) {
    if (resolution1 != null &&
        resolution2 != null &&
        resolution1 != resolution2) {
      return VariantType.resolution;
    }
    if (language1 != null && language2 != null && language1 != language2) {
      return VariantType.language;
    }
    if (format1 != null && format2 != null && format1 != format2) {
      return VariantType.format;
    }
    return null;
  }

  /// Find siblings from a list of content items
  List<ContentSibling> findSiblings({
    required String targetTitle,
    required String targetCid,
    required List<Map<String, dynamic>> candidates,
  }) {
    final siblings = <ContentSibling>[];

    for (final candidate in candidates) {
      final candidateCid = candidate['cid'] as String?;
      final candidateTitle = candidate['title'] as String?;

      if (candidateCid == null || candidateTitle == null) continue;
      if (candidateCid == targetCid) continue; // Skip self

      final similarity = calculateSimilarity(targetTitle, candidateTitle);

      if (similarity >= _similarityThreshold) {
        final variantType = detectVariantType(
          resolution1: candidate['resolution'] as String?,
          resolution2: null, // Would come from target metadata
          language1: candidate['language'] as String?,
          language2: null,
          format1: candidate['format'] as String?,
          format2: null,
        );

        siblings.add(
          ContentSibling(
            cid: candidateCid,
            title: candidateTitle,
            similarity: similarity,
            variantType: variantType,
            variantValue: _getVariantValue(candidate, variantType),
          ),
        );
      }
    }

    // Sort by similarity descending
    siblings.sort((a, b) => b.similarity.compareTo(a.similarity));
    return siblings;
  }

  String? _getVariantValue(Map<String, dynamic> item, VariantType? type) {
    if (type == null) return null;
    switch (type) {
      case VariantType.resolution:
        return item['resolution'] as String?;
      case VariantType.language:
        return item['language'] as String?;
      case VariantType.format:
        return item['format'] as String?;
      case VariantType.quality:
        return item['quality'] as String?;
      case VariantType.edition:
        return item['edition'] as String?;
    }
  }

  /// Select the "best" version from siblings based on preferences
  String? selectBestVersion(
    List<ContentSibling> siblings, {
    String? preferredResolution,
    String? preferredLanguage,
    String? preferredFormat,
  }) {
    if (siblings.isEmpty) return null;

    // Score each sibling based on preferences
    var bestScore = -1.0;
    ContentSibling? best;

    for (final sibling in siblings) {
      var score = sibling.similarity;

      // Boost preferred variants
      if (preferredResolution != null &&
          sibling.variantType == VariantType.resolution &&
          sibling.variantValue == preferredResolution) {
        score += 0.1;
      }
      if (preferredLanguage != null &&
          sibling.variantType == VariantType.language &&
          sibling.variantValue == preferredLanguage) {
        score += 0.1;
      }
      if (preferredFormat != null &&
          sibling.variantType == VariantType.format &&
          sibling.variantValue == preferredFormat) {
        score += 0.1;
      }

      if (score > bestScore) {
        bestScore = score;
        best = sibling;
      }
    }

    return best?.cid;
  }

  /// Group content by root CID (for version trees)
  Map<String, List<String>> groupByRoot(List<Map<String, dynamic>> items) {
    final groups = <String, List<String>>{};

    for (final item in items) {
      final cid = item['cid'] as String?;
      final rootCid = item['rootCid'] as String? ?? cid;

      if (cid == null) continue;

      groups.putIfAbsent(rootCid!, () => []);
      groups[rootCid]!.add(cid);
    }

    return groups;
  }
}
