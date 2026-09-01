import 'package:flutter_riverpod/flutter_riverpod.dart';

final comicMediaServiceProvider = Provider((ref) => ComicMediaService());

class ComicInfoMetadata {
  final String? title;
  final String? series;
  final int? number;
  final String? writer;
  final String? penciller;
  final String? summary;
  final int pageCount;

  ComicInfoMetadata({
    this.title,
    this.series,
    this.number,
    this.writer,
    this.penciller,
    this.summary,
    required this.pageCount,
  });
}

class ComicMediaService {
  ComicInfoMetadata parseComicInfoXml(String xmlContent) {
    final titleMatch = RegExp(r'<Title>(.*?)</Title>').firstMatch(xmlContent);
    final seriesMatch =
        RegExp(r'<Series>(.*?)</Series>').firstMatch(xmlContent);
    final numMatch = RegExp(r'<Number>(.*?)</Number>').firstMatch(xmlContent);
    final writerMatch =
        RegExp(r'<Writer>(.*?)</Writer>').firstMatch(xmlContent);
    final pencillerMatch =
        RegExp(r'<Penciller>(.*?)</Penciller>').firstMatch(xmlContent);
    final summaryMatch =
        RegExp(r'<Summary>(.*?)</Summary>').firstMatch(xmlContent);
    final pageCountMatch =
        RegExp(r'<PageCount>(\d+)</PageCount>').firstMatch(xmlContent);

    return ComicInfoMetadata(
      title: titleMatch?.group(1),
      series: seriesMatch?.group(1),
      number: numMatch != null ? int.tryParse(numMatch.group(1)!) : null,
      writer: writerMatch?.group(1),
      penciller: pencillerMatch?.group(1),
      summary: summaryMatch?.group(1),
      pageCount: pageCountMatch != null
          ? int.tryParse(pageCountMatch.group(1)!) ?? 0
          : 0,
    );
  }

  List<String> sortPagesNaturally(List<String> filenames) {
    final sorted = List<String>.from(filenames);
    sorted.sort((a, b) {
      final numA = _extractNumber(a);
      final numB = _extractNumber(b);
      if (numA != null && numB != null) return numA.compareTo(numB);
      return a.compareTo(b);
    });
    return sorted;
  }

  int? _extractNumber(String s) {
    final match = RegExp(r'(\d+)').firstMatch(s);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }
}
