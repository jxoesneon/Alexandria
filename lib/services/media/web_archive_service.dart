import 'package:flutter_riverpod/flutter_riverpod.dart';

final webArchiveServiceProvider = Provider((ref) => WebArchiveService());

class WarcRecordHeader {
  final String recordType;
  final String? targetUri;
  final String? date;
  final int contentLength;

  WarcRecordHeader({
    required this.recordType,
    this.targetUri,
    this.date,
    required this.contentLength,
  });
}

class WebArchiveService {
  WarcRecordHeader parseWarcHeader(String headerText) {
    if (!headerText.startsWith('WARC/1.')) {
      throw const FormatException('Invalid WARC protocol version header');
    }

    final typeMatch = RegExp(r'WARC-Type:\s*([^\r\n]+)', caseSensitive: false)
        .firstMatch(headerText);
    final uriMatch =
        RegExp(r'WARC-Target-URI:\s*([^\r\n]+)', caseSensitive: false)
            .firstMatch(headerText);
    final dateMatch = RegExp(r'WARC-Date:\s*([^\r\n]+)', caseSensitive: false)
        .firstMatch(headerText);
    final lenMatch = RegExp(r'Content-Length:\s*(\d+)', caseSensitive: false)
        .firstMatch(headerText);

    return WarcRecordHeader(
      recordType: typeMatch?.group(1) ?? 'unknown',
      targetUri: uriMatch?.group(1),
      date: dateMatch?.group(1),
      contentLength:
          lenMatch != null ? int.tryParse(lenMatch.group(1)!) ?? 0 : 0,
    );
  }
}
