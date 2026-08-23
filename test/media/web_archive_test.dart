import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/web_archive_service.dart';

void main() {
  group('Web Archive (WARC) Parser Tests', () {
    late WebArchiveService webArchiveService;

    setUp(() {
      webArchiveService = WebArchiveService();
    });

    test('parses WARC/1.0 response record header', () {
      const warc = '''WARC/1.0
WARC-Type: response
WARC-Target-URI: https://archive.example.org/snapshot
WARC-Date: 2026-08-23T12:00:00Z
Content-Length: 4096
''';

      final header = webArchiveService.parseWarcHeader(warc);
      expect(header.recordType, equals('response'));
      expect(header.targetUri, equals('https://archive.example.org/snapshot'));
      expect(header.contentLength, equals(4096));
    });
  });
}
