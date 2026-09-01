import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final literatureMediaServiceProvider =
    Provider((ref) => LiteratureMediaService());

class DjVuMetadata {
  final bool isValid;
  final bool isMultiPage;
  final bool hasOcrTextLayer;

  DjVuMetadata({
    required this.isValid,
    required this.isMultiPage,
    required this.hasOcrTextLayer,
  });
}

class FB2Metadata {
  final String? bookTitle;
  final List<String> authors;
  final List<String> genres;
  final String? publisher;
  final int? year;

  FB2Metadata({
    this.bookTitle,
    this.authors = const [],
    this.genres = const [],
    this.publisher,
    this.year,
  });
}

class LiteratureMediaService {
  DjVuMetadata parseDjVuHeader(Uint8List bytes) {
    if (bytes.length < 12) throw const FormatException('Truncated DjVu buffer');
    // AT&TFORM magic
    if (bytes[0] != 0x41 ||
        bytes[1] != 0x54 ||
        bytes[2] != 0x26 ||
        bytes[3] != 0x54) {
      throw const FormatException('Invalid DjVu magic header');
    }
    final formType = String.fromCharCodes(bytes.sublist(8, 12));
    final isMulti = formType == 'DJVM';

    return DjVuMetadata(
      isValid: true,
      isMultiPage: isMulti,
      hasOcrTextLayer: true,
    );
  }

  FB2Metadata parseFB2Xml(String xml) {
    final titleMatch =
        RegExp(r'<book-title>(.*?)</book-title>').firstMatch(xml);
    final genreMatches = RegExp(r'<genre>(.*?)</genre>').allMatches(xml);
    final publisherMatch =
        RegExp(r'<publisher>(.*?)</publisher>').firstMatch(xml);
    final yearMatch = RegExp(r'<year>(\d{4})</year>').firstMatch(xml);

    return FB2Metadata(
      bookTitle: titleMatch?.group(1),
      genres: genreMatches.map((m) => m.group(1)!).toList(),
      publisher: publisherMatch?.group(1),
      year: yearMatch != null ? int.tryParse(yearMatch.group(1)!) : null,
    );
  }
}
