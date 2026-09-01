import 'package:flutter_riverpod/flutter_riverpod.dart';

final academicMediaServiceProvider = Provider((ref) => AcademicMediaService());

class LatexDocumentMetadata {
  final String? title;
  final List<String> authors;
  final String? abstractText;
  final List<String> packages;
  final List<String> citations;

  LatexDocumentMetadata({
    this.title,
    this.authors = const [],
    this.abstractText,
    this.packages = const [],
    this.citations = const [],
  });
}

class BibtexEntry {
  final String key;
  final String type;
  final String title;
  final List<String> authors;
  final int? year;

  BibtexEntry({
    required this.key,
    required this.type,
    required this.title,
    this.authors = const [],
    this.year,
  });
}

class JupyterNotebookMetadata {
  final String? title;
  final int codeCellCount;
  final int markdownCellCount;
  final String? kernelLanguage;

  JupyterNotebookMetadata({
    this.title,
    required this.codeCellCount,
    required this.markdownCellCount,
    this.kernelLanguage,
  });
}

class AcademicMediaService {
  LatexDocumentMetadata parseLatex(String source) {
    final titleMatch = RegExp(r'\\title\{([^}]+)\}').firstMatch(source);
    final title = titleMatch?.group(1);

    final authorMatch = RegExp(r'\\author\{([^}]+)\}').firstMatch(source);
    final authors = authorMatch != null
        ? authorMatch
            .group(1)!
            .split(RegExp(r'\\and|,'))
            .map((a) => a.trim())
            .toList()
        : <String>[];

    final abstractMatch =
        RegExp(r'\\begin\{abstract\}([\s\S]*?)\\end\{abstract\}')
            .firstMatch(source);
    final abstractText = abstractMatch?.group(1)?.trim();

    final packageMatches =
        RegExp(r'\\usepackage(?:\[[^\]]*\])?\{([^}]+)\}').allMatches(source);
    final packages = packageMatches.map((m) => m.group(1)!).toList();

    final citeMatches = RegExp(r'\\cite\{([^}]+)\}').allMatches(source);
    final citations = citeMatches
        .expand((m) => m.group(1)!.split(','))
        .map((c) => c.trim())
        .toList();

    return LatexDocumentMetadata(
      title: title,
      authors: authors,
      abstractText: abstractText,
      packages: packages,
      citations: citations,
    );
  }

  List<BibtexEntry> parseBibtex(String source) {
    final entries = <BibtexEntry>[];
    final entryRegex =
        RegExp(r'@(\w+)\s*\{\s*([^,]+),([\s\S]*?)\n\s*\}', multiLine: true);

    for (final match in entryRegex.allMatches(source)) {
      final type = match.group(1)!;
      final key = match.group(2)!;
      final body = match.group(3)!;

      final titleMatch =
          RegExp(r'title\s*=\s*[\{"]([^"\}]+)[\}"]', caseSensitive: false)
              .firstMatch(body);
      final title = titleMatch?.group(1) ?? 'Untitled';

      final authorMatch =
          RegExp(r'author\s*=\s*[\{"]([^"\}]+)[\}"]', caseSensitive: false)
              .firstMatch(body);
      final authors = authorMatch != null
          ? authorMatch.group(1)!.split(' and ').map((a) => a.trim()).toList()
          : <String>[];

      final yearMatch =
          RegExp(r'year\s*=\s*[\{"]?(\d{4})[\}"]?', caseSensitive: false)
              .firstMatch(body);
      final year = yearMatch != null ? int.tryParse(yearMatch.group(1)!) : null;

      entries.add(BibtexEntry(
        key: key,
        type: type,
        title: title,
        authors: authors,
        year: year,
      ));
    }
    return entries;
  }
}
