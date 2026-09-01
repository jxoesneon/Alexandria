import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/software_heritage_service.dart';

void main() {
  group('Software Heritage Parser Tests', () {
    late SoftwareHeritageService softwareService;

    setUp(() {
      softwareService = SoftwareHeritageService();
    });

    test('parses Git bundle header with references', () {
      const header = '''# v2 git bundle
-7b43e16eb4df16f8b570170636111719b6b2172
879c17fc869a56a5dea1f02827a65024dc6cbbdf refs/heads/main
''';

      final meta = softwareService.parseGitBundleHeader(header);
      expect(meta.version, equals('v2 git bundle'));
      expect(meta.prerequisiteCommitIds.length, equals(1));
      expect(meta.references['refs/heads/main'],
          equals('879c17fc869a56a5dea1f02827a65024dc6cbbdf'));
    });

    test('parses WASM binary module header', () {
      final wasm = Uint8List.fromList([
        0x00, 0x61, 0x73, 0x6D, // '\0asm'
        0x01, 0x00, 0x00, 0x00, // version 1
      ]);

      final meta = softwareService.parseWasmHeader(wasm);
      expect(meta.version, equals(1));
      expect(meta.functionCount, greaterThan(0));
    });
  });
}
