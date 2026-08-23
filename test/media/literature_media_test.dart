import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/literature_media_service.dart';

void main() {
  group('Literature & Scanned Book Parser Tests', () {
    late LiteratureMediaService literatureService;

    setUp(() {
      literatureService = LiteratureMediaService();
    });

    test('parses DjVu header and flags multi-page document', () {
      final header = Uint8List(12);
      header[0] = 0x41; // 'A'
      header[1] = 0x54; // 'T'
      header[2] = 0x26; // '&'
      header[3] = 0x54; // 'T'
      header[4] = 0x46; // 'F'
      header[5] = 0x4F; // 'O'
      header[6] = 0x52; // 'R'
      header[7] = 0x4D; // 'M'
      header[8] = 0x44; // 'D'
      header[9] = 0x4A; // 'J'
      header[10] = 0x56; // 'V'
      header[11] = 0x4D; // 'M'

      final meta = literatureService.parseDjVuHeader(header);
      expect(meta.isValid, isTrue);
      expect(meta.isMultiPage, isTrue);
      expect(meta.hasOcrTextLayer, isTrue);
    });

    test('parses FictionBook (FB2) XML metadata', () {
      const fb2 = '''
      <?xml version="1.0" encoding="utf-8"?>
      <FictionBook>
        <description>
          <title-info>
            <genre>sf_history</genre>
            <book-title>The Time Machine</book-title>
            <year>1895</year>
          </title-info>
          <publish-info>
            <publisher>Heinemann</publisher>
          </publish-info>
        </description>
      </FictionBook>
      ''';

      final meta = literatureService.parseFB2Xml(fb2);
      expect(meta.bookTitle, equals('The Time Machine'));
      expect(meta.genres, contains('sf_history'));
      expect(meta.publisher, equals('Heinemann'));
      expect(meta.year, equals(1895));
    });
  });
}
