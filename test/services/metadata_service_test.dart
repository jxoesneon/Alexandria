import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataExtractionService', () {
    late MetadataExtractionService service;

    setUp(() {
      service = MetadataExtractionService();
    });

    test('extracts basic info for an unknown binary file', () async {
      final file = PlatformFile(
        name: 'data.bin',
        size: 42,
        bytes: Uint8List(42),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['size_bytes'], 42);
      expect(metadata['format'], 'bin');
      expect(metadata.containsKey('resolution'), isFalse);
    });

    test('extracts format for image without crashing on missing EXIF data',
        () async {
      final file = PlatformFile(
        name: 'photo.jpg',
        size: 0,
        bytes: Uint8List(0),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['size_bytes'], 0);
      expect(metadata['format'], 'jpg');
    });

    test('returns the extension as the format', () async {
      final file = PlatformFile(
        name: 'file.unknown',
        size: 10,
        bytes: Uint8List(10),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['format'], 'unknown');
    });

    test('counts rows for a CSV file', () async {
      final tempDir = await Directory.systemTemp.createTemp('metadata_test');
      final csvFile = File('${tempDir.path}/data.csv');
      await csvFile.writeAsString('a,b\nc,d\ne,f\n');

      final file = PlatformFile(
        name: 'data.csv',
        path: csvFile.path,
        size: await csvFile.length(),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['format'], 'csv');
      expect(metadata['row_count'], 3);

      await tempDir.delete(recursive: true);
    });

    test('counts lines for a code file', () async {
      final tempDir = await Directory.systemTemp.createTemp('metadata_test');
      final codeFile = File('${tempDir.path}/main.dart');
      await codeFile.writeAsString('void main() {\n  print("ok");\n}\n');

      final file = PlatformFile(
        name: 'main.dart',
        path: codeFile.path,
        size: await codeFile.length(),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['format'], 'dart');
      expect(metadata['dependencies'], 3);

      await tempDir.delete(recursive: true);
    });

    test('counts rows for a JSON file', () async {
      final tempDir = await Directory.systemTemp.createTemp('metadata_test');
      final jsonFile = File('${tempDir.path}/data.json');
      await jsonFile.writeAsString('[1, 2]\n[3, 4]\n[5, 6]\n');

      final file = PlatformFile(
        name: 'data.json',
        path: jsonFile.path,
        size: await jsonFile.length(),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['format'], 'json');
      expect(metadata['row_count'], 3);

      await tempDir.delete(recursive: true);
    });

    test('counts dependencies for a YAML file', () async {
      final tempDir = await Directory.systemTemp.createTemp('metadata_test');
      final yamlFile = File('${tempDir.path}/pubspec.yaml');
      await yamlFile.writeAsString('name: app\nversion: 1.0.0\n');

      final file = PlatformFile(
        name: 'pubspec.yaml',
        path: yamlFile.path,
        size: await yamlFile.length(),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['format'], 'yaml');
      expect(metadata['dependencies'], 2);

      await tempDir.delete(recursive: true);
    });

    test('lowercases file extensions', () async {
      final file = PlatformFile(
        name: 'Archive.JPG',
        size: 10,
        bytes: Uint8List(10),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['format'], 'jpg');
    });

    test('handles a PNG file without crashing', () async {
      final file = PlatformFile(
        name: 'icon.png',
        size: 4,
        bytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['format'], 'png');
      expect(metadata.containsKey('resolution'), isFalse);
    });

    test('metadataServiceProvider is readable', () {
      final container = ProviderContainer();
      final service = container.read(metadataServiceProvider);
      expect(service, isA<MetadataExtractionService>());
      container.dispose();
    });

    test('handles decoding errors for text files gracefully', () async {
      final tempDir = await Directory.systemTemp.createTemp('metadata_test');
      final jsonFile = File('${tempDir.path}/bad.json');
      // Invalid UTF-8 sequence.
      await jsonFile.writeAsBytes([0x80, 0x81, 0x82]);

      final file = PlatformFile(
        name: 'bad.json',
        path: jsonFile.path,
        size: await jsonFile.length(),
      );

      final metadata = await service.extractMetadata(file);

      expect(metadata['format'], 'json');
      expect(metadata.containsKey('row_count'), isFalse);

      await tempDir.delete(recursive: true);
    });
  });

  group('MetadataExtractionService non-EXIF branches', () {
    late MetadataExtractionService service;

    setUp(() {
      service = MetadataExtractionService();
    });

    Future<PlatformFile> writeTemp(String name, String content) async {
      final tempDir = await Directory.systemTemp.createTemp('metadata_test');
      final f = File('${tempDir.path}/$name');
      await f.writeAsString(content);
      return PlatformFile(name: name, path: f.path, size: await f.length());
    }

    test('counts dependencies for markdown files', () async {
      final file = await writeTemp('notes.md', '# Title\n\nbody\n');
      final metadata = await service.extractMetadata(file);
      expect(metadata['format'], 'md');
      expect(metadata['dependencies'], 3);
    });

    test('counts dependencies for C source files', () async {
      final file =
          await writeTemp('main.c', '#include <stdio.h>\nint main(){}\n');
      final metadata = await service.extractMetadata(file);
      expect(metadata['format'], 'c');
      expect(metadata['dependencies'], 2);
    });

    test('counts dependencies for JSON files', () async {
      final file = await writeTemp('data.json', '{"a":1}\n{"b":2}\n');
      final metadata = await service.extractMetadata(file);
      expect(metadata['format'], 'json');
      expect(metadata['row_count'], 2);
    });

    test('counts dependencies for XML files', () async {
      final file = await writeTemp('data.xml', '<a/>\n<b/>\n');
      final metadata = await service.extractMetadata(file);
      expect(metadata['format'], 'xml');
      expect(metadata['row_count'], 2);
    });

    test('counts dependencies for YAML and YML', () async {
      final yaml = await writeTemp('data.yaml', 'a: 1\nb: 2\n');
      final yml = await writeTemp('data.yml', 'x: 1');

      final yamlMeta = await service.extractMetadata(yaml);
      final ymlMeta = await service.extractMetadata(yml);

      expect(yamlMeta['dependencies'], 2);
      expect(yamlMeta['format'], 'yaml');
      expect(ymlMeta['dependencies'], 1);
      expect(ymlMeta['format'], 'yml');
    });

    test('counts dependencies for other code formats', () async {
      final py = await writeTemp('script.py', 'print(1)\nprint(2)\n');
      final js = await writeTemp('script.js', 'a\nb\n');
      final html = await writeTemp('page.html', '<html>\n</html>\n');

      final pyMeta = await service.extractMetadata(py);
      final jsMeta = await service.extractMetadata(js);
      final htmlMeta = await service.extractMetadata(html);

      expect(pyMeta['dependencies'], 2);
      expect(jsMeta['dependencies'], 2);
      expect(htmlMeta['dependencies'], 2);
    });

    test('handles missing file path for text formats gracefully', () async {
      final file = PlatformFile(
        name: 'orphan.txt',
        size: 10,
      );
      final metadata = await service.extractMetadata(file);
      expect(metadata['format'], 'txt');
      expect(metadata.containsKey('dependencies'), isFalse);
    });

    test('lowercases format for mixed-case extensions', () async {
      final file = PlatformFile(name: 'README.MD', size: 0);
      final metadata = await service.extractMetadata(file);
      expect(metadata['format'], 'md');
    });

    test('falls back to the file name as the format when there is no extension',
        () async {
      final file = PlatformFile(name: 'README', size: 0);
      final metadata = await service.extractMetadata(file);
      expect(metadata['format'], 'readme');
    });
  });
}
