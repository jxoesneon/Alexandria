import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final siblingServiceProvider = Provider((ref) => SiblingService());
const double _similarityThreshold = 0.85;

enum VariantType { resolution, language, format, quality, edition }

class ContentSibling {
  final String cid;
  final String title;
  final double similarity;
  final VariantType? variantType;
  final String? variantValue;

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

class SiblingService {
  /// Maps a wire variant name to [VariantType] without throwing —
  /// `Enum.values.byName` would crash on a remote-supplied unknown name.
  static VariantType? _variantTypeFromWire(Object? raw) {
    if (raw is! String) return null;
    for (final t in VariantType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }

  String normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _stripVariantSuffix(String title) {
    return title
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int levenshteinDistance(String s1, String s2) {
    final m = s1.length;
    final n = s2.length;
    final d = List.generate(m + 1, (_) => List.filled(n + 1, 0));

    for (var i = 0; i <= m; i++) {
      d[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      d[0][j] = j;
    }

    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + cost,
        ].reduce(min);
      }
    }
    return d[m][n];
  }

  /// Upper bound on title length fed into the O(m·n) Levenshtein matrix —
  /// attacker-sized titles would otherwise allocate quadratic memory/CPU
  /// (red minor-observation hardening).
  static const int maxTitleLength = 512;

  double calculateSimilarity(String s1, String s2) {
    var n1 = normalizeTitle(_stripVariantSuffix(s1));
    var n2 = normalizeTitle(_stripVariantSuffix(s2));
    if (n1.length > maxTitleLength) n1 = n1.substring(0, maxTitleLength);
    if (n2.length > maxTitleLength) n2 = n2.substring(0, maxTitleLength);
    if (n1.isEmpty || n2.isEmpty) return 0.0;
    if (n1 == n2) return 1.0;
    final maxLen = max(n1.length, n2.length);
    return 1.0 - (levenshteinDistance(n1, n2) / maxLen);
  }

  bool areSiblings(String title1, String title2) {
    return calculateSimilarity(title1, title2) >= _similarityThreshold;
  }

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

  List<ContentSibling> findSiblings({
    required String targetTitle,
    required String targetCid,
    required List<Map<String, dynamic>> candidates,
  }) {
    final siblings = <ContentSibling>[];
    for (final candidate in candidates) {
      final candidateCid = candidate['cid'] as String?;
      final candidateTitle = candidate['title'] as String?;
      if (candidateCid == null ||
          candidateTitle == null ||
          candidateCid == targetCid) {
        continue;
      }

      final similarity = calculateSimilarity(targetTitle, candidateTitle);
      if (similarity >= _similarityThreshold) {
        siblings.add(ContentSibling(
          cid: candidateCid,
          title: candidateTitle,
          similarity: similarity,
          // Non-throwing lookup: remote candidates can carry variant
          // names this build doesn't know — an unknown name degrades to
          // null instead of throwing out of the scan (red hardening).
          variantType: _variantTypeFromWire(candidate['variantType']),
          variantValue: candidate['variantValue'] as String?,
        ));
      }
    }
    siblings.sort((a, b) => b.similarity.compareTo(a.similarity));
    return siblings;
  }
}
