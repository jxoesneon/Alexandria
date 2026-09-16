import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';
import 'package:exif/exif.dart';
import '../fixtures/exif_fixture_generator.dart';

void main() {
  group('MetadataScrubbingService Tests', () {
    late CidService cidService;
    late MetadataScrubbingService scrubbingService;

    setUp(() {
      cidService = CidService();
      scrubbingService = MetadataScrubbingService(cidService);
    });

    test('metadataScrubbingServiceProvider provides instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(metadataScrubbingServiceProvider);
      expect(service, isA<MetadataScrubbingService>());
    });

    test('detectFileType identifies supported headers', () {
      // Short buffer returns null
      expect(scrubbingService.detectFileType(Uint8List(5)), isNull);

      // JPEG magic: 0xFF, 0xD8, 0xFF
      final jpegBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, ...List.filled(10, 0)]);
      expect(scrubbingService.detectFileType(jpegBytes), equals('image/jpeg'));

      // PNG magic: 0x89, 0x50, 0x4E, 0x47
      final pngBytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...List.filled(10, 0)]);
      expect(scrubbingService.detectFileType(pngBytes), equals('image/png'));

      // PDF magic: 0x25, 0x50, 0x44, 0x46 (%PDF)
      final pdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, ...List.filled(10, 0)]);
      expect(scrubbingService.detectFileType(pdfBytes), equals('application/pdf'));

      // MP4: ftyp in 4..8
      final mp4Bytes = Uint8List.fromList([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70, ...List.filled(10, 0)]);
      expect(scrubbingService.detectFileType(mp4Bytes), equals('video/mp4'));

      // HEIC: ftyp + heic in 4..12
      final heicBytes = Uint8List.fromList([0, 0, 0, 0, ...'ftypheic'.codeUnits, ...List.filled(5, 0)]);
      expect(scrubbingService.detectFileType(heicBytes), equals('image/heic'));

      // Unknown
      final unknownBytes = Uint8List.fromList(List.filled(20, 0x01));
      expect(scrubbingService.detectFileType(unknownBytes), isNull);
    });

    test('isSupportedType returns true for images and false for others', () {
      expect(scrubbingService.isSupportedType('image/jpeg'), isTrue);
      expect(scrubbingService.isSupportedType('image/png'), isTrue);
      // HEIC/HEIF/TIFF are detectable but NOT safely scrubbed — the
      // scrubber claims support only for formats it can verifiably
      // rewrite (round-3 red finding).
      expect(scrubbingService.isSupportedType('image/heic'), isFalse);
      expect(scrubbingService.isSupportedType('image/heif'), isFalse);
      expect(scrubbingService.isSupportedType('image/tiff'), isFalse);

      expect(scrubbingService.isSupportedType('application/pdf'), isFalse);
      expect(scrubbingService.isSupportedType('video/mp4'), isFalse);
      expect(scrubbingService.isSupportedType('text/plain'), isFalse);
    });

    test('extractMetadata and detectSensitiveFields on plain bytes return null/empty gracefully', () async {
      final plainBytes = Uint8List.fromList('Just some random text without EXIF'.codeUnits);

      final metadata = await scrubbingService.extractMetadata(plainBytes);
      expect(metadata, isNull);

      final sensitive = await scrubbingService.detectSensitiveFields(plainBytes);
      expect(sensitive, isEmpty);
    });

    test('scrubMetadata returns ScrubbingResult with recalculated CID', () async {
      final sampleBytes = Uint8List.fromList('Simple media byte sequence'.codeUnits);

      final result = await scrubbingService.scrubMetadata(
        sampleBytes,
        options: ScrubbingOptions.full,
      );

      expect(result.originalSize, equals(sampleBytes.length));
      expect(result.scrubbedSize, equals(sampleBytes.length));
      expect(result.sizeReduction, equals(0));
      expect(result.wasModified, isFalse);
      expect(result.newCid, isNotEmpty);
      expect(result.newCid, equals(cidService.cidFromBytes(sampleBytes)));
    });

    test('ScrubbableFields and ScrubbingOptions check all properties', () {
      expect(ScrubbableFields.gpsFields, isNotEmpty);
      expect(ScrubbableFields.deviceFields, isNotEmpty);
      expect(ScrubbableFields.authorFields, isNotEmpty);
      expect(ScrubbableFields.timestampFields, isNotEmpty);
      expect(ScrubbableFields.allFields.length,
          equals(ScrubbableFields.gpsFields.length +
              ScrubbableFields.deviceFields.length +
              ScrubbableFields.authorFields.length +
              ScrubbableFields.timestampFields.length));

      const fullOpts = ScrubbingOptions.full;
      expect(fullOpts.removeGps, isTrue);
      expect(fullOpts.removeDevice, isTrue);
      expect(fullOpts.removeAuthor, isTrue);
      expect(fullOpts.removeTimestamps, isTrue);
      expect(fullOpts.fieldsToRemove.length, equals(ScrubbableFields.allFields.length));

      const privacyOpts = ScrubbingOptions.privacy;
      expect(privacyOpts.removeTimestamps, isFalse);
      expect(privacyOpts.fieldsToRemove.length,
          lessThan(ScrubbableFields.allFields.length));
    });

    test('ExtractedMetadata helper properties and parsing', () {
      final meta = ExtractedMetadata(
        exif: {'Image Make': 'Nikon'},
        gpsLocation: '37.7749, -122.4194',
        cameraMake: 'Nikon',
        cameraModel: 'D850',
        author: 'Alexandria Archivist',
        dateTime: DateTime(2026, 1, 1, 12, 0),
      );

      expect(meta.hasLocation, isTrue);
      expect(meta.hasDeviceInfo, isTrue);
      expect(meta.hasAuthor, isTrue);
      expect(meta.exif['Image Make'], equals('Nikon'));
    });

    test('extractMetadata correctly parses EXIF tags from real EXIF JPEG', () async {
      final jpegBytes = buildSampleExifJpeg(useExifDateTime: true);
      final meta = await scrubbingService.extractMetadata(jpegBytes);

      expect(meta, isNotNull);
      expect(meta!.hasLocation, isTrue);
      expect(meta.gpsLocation, contains('37'));
      expect(meta.hasDeviceInfo, isTrue);
      expect(meta.cameraMake, equals('Sony'));
      expect(meta.cameraModel, equals('A7R IV'));
      expect(meta.hasAuthor, isTrue);
      expect(meta.author, equals('Alexandria'));
      expect(meta.dateTime, equals(DateTime(2023, 5, 1, 12, 0, 0)));
    });

    test('detectSensitiveFields and scrubMetadata detect and record scrubbed fields', () async {
      final jpegBytes = buildSampleExifJpeg();
      final sensitive = await scrubbingService.detectSensitiveFields(jpegBytes);

      expect(sensitive, contains('GPS GPSLatitude'));
      expect(sensitive, contains('GPS GPSLongitude'));
      expect(sensitive, contains('Image Model'));
      expect(sensitive, contains('Image Make'));

      final scrubResult = await scrubbingService.scrubMetadata(
        jpegBytes,
        options: ScrubbingOptions.full,
      );
      expect(scrubResult.removedFields, contains('GPS GPSLatitude'));
      expect(scrubResult.removedFields, contains('Image Make'));
      expect(scrubResult.wasModified, isTrue);
    });

    test('ExtractedMetadata.fromExifData handles invalid date strings gracefully', () {
      final meta1 = ExtractedMetadata.fromExifData({
        'EXIF DateTimeOriginal': null,
      });
      expect(meta1.dateTime, isNull);

      final meta2 = ExtractedMetadata.fromExifData({
        'EXIF DateTimeOriginal': IfdTag(
          tag: 0x9003,
          tagType: 'ASCII',
          printable: 'InvalidDateTimeString',
          values: const IfdNone(),
        ),
      });
      expect(meta2.dateTime, isNull);

      final meta3 = ExtractedMetadata.fromExifData({
        'EXIF DateTimeOriginal': IfdTag(
          tag: 0x9003,
          tagType: 'ASCII',
          printable: '2023:05 12:00:00', // incomplete date
          values: const IfdNone(),
        ),
      });
      expect(meta3.dateTime, isNull);
    });
  });

  group('scrubMetadata input ceiling (campaign-2 service-side bound)', () {
    test('refuses input over the ceiling explicitly', () async {
      final bounded =
          MetadataScrubbingService(CidService(), maxInputBytes: 64);
      final oversized = Uint8List(65); // valid PNG-signature head below
      oversized.setRange(
          0, 8, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(
        () => bounded.scrubMetadata(oversized),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('accepts input at exactly the ceiling', () async {
      final bounded =
          MetadataScrubbingService(CidService(), maxInputBytes: 64);
      final atCeiling = Uint8List(64);
      atCeiling.setRange(
          0, 8, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      // No throw — 64 <= 64 is inside the bound.
      final result = await bounded.scrubMetadata(atCeiling);
      expect(result.originalSize, equals(64));
    });

    test('default ceiling is the 512 MiB ingest bound', () {
      expect(MetadataScrubbingService.defaultMaxInputBytes,
          equals(512 * 1024 * 1024));
      expect(MetadataScrubbingService(CidService()).maxInputBytes,
          equals(MetadataScrubbingService.defaultMaxInputBytes));
    });
  });
}
