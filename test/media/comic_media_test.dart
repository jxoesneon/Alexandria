import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/comic_media_service.dart';

void main() {
  group('Comic Media Parser Tests', () {
    late ComicMediaService comicService;

    setUp(() {
      comicService = ComicMediaService();
    });

    test('parses ComicInfo.xml metadata correctly', () {
      const xml = '''
      <ComicInfo>
        <Title>Sample Comic Issue 1</Title>
        <Series>Alexandria Chronicles</Series>
        <Number>1</Number>
        <Writer>Alan Moore</Writer>
        <Penciller>Dave Gibbons</Penciller>
        <Summary>A historical exploration of preserved knowledge.</Summary>
        <PageCount>32</PageCount>
      </ComicInfo>
      ''';

      final info = comicService.parseComicInfoXml(xml);
      expect(info.title, equals('Sample Comic Issue 1'));
      expect(info.series, equals('Alexandria Chronicles'));
      expect(info.number, equals(1));
      expect(info.writer, equals('Alan Moore'));
      expect(info.pageCount, equals(32));
    });

    test('sorts comic page filenames naturally', () {
      final pages = ['page_10.jpg', 'page_1.jpg', 'page_2.jpg', 'cover.jpg'];
      final sorted = comicService.sortPagesNaturally(pages);

      expect(sorted[0], equals('cover.jpg'));
      expect(sorted[1], equals('page_1.jpg'));
      expect(sorted[2], equals('page_2.jpg'));
      expect(sorted[3], equals('page_10.jpg'));
    });
  });
}
