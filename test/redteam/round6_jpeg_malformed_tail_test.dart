// RED TEAM PoC — Round-6: the JPEG scrubber's malformed-input bail-out
// is FAIL-OPEN for privacy. Every "we cannot parse this" branch in
// _stripJpegMetadataSegments resolves by copying the remainder of the
// stream VERBATIM:
//
//   lib/services/metadata_scrubbing_service.dart
//     :329-333  bytes[i] != 0xFF at a marker boundary → sublist(i) verbatim
//     :356-359  marker == 0x00 (stream fell out of entropy mode) → verbatim
//     :371-375  segLen < 2 || past EOF                      → verbatim
//
// Anything metadata-bearing AFTER the malformed point — a complete,
// valid APP1/Exif segment with GPS coordinates — ships inside
// `scrubbedBytes` untouched. Worse, the exif-3.3.0 reader used for both
// pre-scrub detection (`wanted`) and post-scrub verification
// (`remaining`) scans only the first ~4 KiB and stops at the FIRST
// Exif APP1 (read_exif.dart:267 `f.readSync(base + 4000)`, and the
// scan loop `break`s on the first 'Exif' APP1). So:
//
//   * wanted/removedFields are populated by APP1#1 (before the fault),
//     which IS stripped — `wasModified` is true and the caller
//     (add_content_screen.dart:473-475) ships `scrubbedBytes`;
//   * `remaining` cannot see APP1#2 past the fault either, so the
//     verification pass reports the fields "genuinely gone" while a
//     full Exif/GPS APP1 sits verbatim in the emitted file — a false
//     "removed" claim AND a privacy leak in one step.
//
// Asserts the SECURE expectation: no 'Exif\0\0' APP1 payload may be
// present anywhere in the scrubbed output.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';
import '../fixtures/exif_fixture_generator.dart';

/// Extracts the complete `FF E1 <len> Exif…` APP1 segment out of the
/// fixture JPEG (SOI ‖ APP1 ‖ EOI).
Uint8List _exifApp1Segment() {
  final jpeg = buildSampleExifJpeg();
  expect(jpeg[0], 0xFF);
  expect(jpeg[1], 0xD8);
  expect(jpeg[2], 0xFF);
  expect(jpeg[3], 0xE1);
  final segLen = (jpeg[4] << 8) | jpeg[5];
  return Uint8List.fromList(jpeg.sublist(2, 2 + 2 + segLen));
}

int _countExifMarkers(Uint8List bytes) {
  var count = 0;
  for (var i = 0; i + 7 < bytes.length; i++) {
    if (bytes[i] == 0xFF &&
        bytes[i + 1] == 0xE1 &&
        bytes[i + 4] == 0x45 && // 'E'
        bytes[i + 5] == 0x78 && // 'x'
        bytes[i + 6] == 0x69 && // 'i'
        bytes[i + 7] == 0x66) {
      // 'f'
      count++;
    }
  }
  return count;
}

const _jfifApp0 = <int>[
  0xFF, 0xE0, 0x00, 0x10, // APP0, length 16
  0x4A, 0x46, 0x49, 0x46, 0x00, // 'JFIF\0'
  0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
];

const _sosAndScan = <int>[
  0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00, // SOS hdr
  0x11, 0x22, 0xFF, 0x00, 0x33, // entropy data (stuffed 0xFF)
  0xFF, 0xD9, // EOI
];

void main() {
  final svc = MetadataScrubbingService(CidService());

  test('APP1 placed after a segment with a corrupt length survives '
      'scrubbing verbatim', () async {
    final app1 = _exifApp1Segment();
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      ..._jfifApp0,
      ...app1, // APP1#1 — parsed, reported, stripped
      // APP2 with a corrupt length field: 0xFFFF runs past EOF, so the
      // walker bails out and copies EVERYTHING below verbatim.
      0xFF, 0xE2, 0xFF, 0xFF, 0x49, 0x43, 0x43, // 'ICC'
      ...app1, // APP1#2 — a second, complete Exif/GPS segment
      ..._sosAndScan,
    ]);

    // Sanity: the pre-scrub detector sees real Exif fields, so the
    // scrub is claimed and `wasModified` ships `scrubbedBytes`.
    expect(await svc.detectSensitiveFields(jpeg), isNotEmpty);

    final result = await svc.scrubMetadata(jpeg);
    expect(_countExifMarkers(result.scrubbedBytes), 0,
        reason:
            'an Exif APP1 placed behind a corrupt-length segment rode '
            'through the scrubber untouched: the bail-out branch copies '
            'the tail verbatim, and the ≤4 KiB exif reader never sees '
            'the survivor, so removedFields can still report the GPS/'
            'device fields as "removed" while they ship in the file.');
  });

  test('APP1 placed after a stray 0xFF00 byte at a marker boundary '
      'survives scrubbing verbatim', () async {
    final app1 = _exifApp1Segment();
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      ..._jfifApp0,
      ...app1, // APP1#1 — stripped
      // Stray stuffed-0xFF byte where a marker is expected: the walker
      // reads marker code 0x00 and copies the rest verbatim.
      0xFF, 0x00,
      ...app1, // APP1#2
      ..._sosAndScan,
    ]);

    final result = await svc.scrubMetadata(jpeg);
    expect(_countExifMarkers(result.scrubbedBytes), 0,
        reason:
            'marker==0x00 bail-out copies the remainder verbatim — a '
            'complete Exif APP1 survives in "scrubbed" output.');
  });

  test('APP1 placed after a non-marker byte at a segment boundary '
      'survives scrubbing verbatim', () async {
    final app1 = _exifApp1Segment();
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      ..._jfifApp0,
      ...app1, // APP1#1 — stripped
      0x42, // non-0xFF byte where a marker must be → verbatim tail
      ...app1, // APP1#2
      ..._sosAndScan,
    ]);

    final result = await svc.scrubMetadata(jpeg);
    expect(_countExifMarkers(result.scrubbedBytes), 0,
        reason:
            'the not-at-marker bail-out copies the remainder verbatim — '
            'Exif metadata after any single corrupt byte survives.');
  });
}
