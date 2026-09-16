// RED TEAM PoC - Round-7: the scrub-adoption gate silently ships the
// ORIGINAL bytes whenever the file's metadata lives in a segment the
// exif-3.3.0 detector cannot see - even though the scrubber itself
// produced a clean stream.
//
//   lib/ui/add_content_screen.dart:470-475
//     if (fileType != null && scrubbingService.isSupportedType(fileType)) {
//       final result = await scrubbingService.scrubMetadata(fileBytes);
//       if (result.wasModified) {                 // ← gate
//         fileBytes = result.scrubbedBytes;
//       }
//     }
//
// `wasModified` is `removedFields.isNotEmpty`, and removedFields is
// populated ONLY from `wanted` - the keys `readExifFromBytes` detected
// intersected with ScrubbableFields. The JPEG scrubber strips
// APP1/APP13/COM unconditionally, but the *detector* only reports Exif
// tags it can parse. So a JPEG whose ONLY metadata is:
//   * a COM (0xFF 0xFE) free-text comment - never EXIF-parseable,
//   * an XMP-only APP1 (no 'Exif\0\0' header), or
//   * an APP13/IPTC block with no accompanying Exif APP1,
// comes back with removedFields == [] → wasModified == false → the UI
// KEEPS THE ORIGINAL BYTES. The user toggled "strip metadata", the
// scrubber DID strip the segment, and the adoption gate threw the
// clean output away and uploaded the file with the comment intact.
//
// This is the same fail-open class the round-6 resync fixed inside the
// walker - moved one layer up into the caller contract.
//
// Asserts the SECURE expectation: when the scrubber actually rewrote
// the byte stream, the caller-visible result must not tell the UI to
// keep the original - the shipped bytes must be the scrubbed ones.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';

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

List<int> _comSegment(String text) {
  final payload = text.codeUnits;
  final len = payload.length + 2;
  return [0xFF, 0xFE, (len >> 8) & 0xFF, len & 0xFF, ...payload];
}

List<int> _xmpApp1(String xmp) {
  const header = 'http://ns.adobe.com/xap/1.0/\x00';
  final payload = [...header.codeUnits, ...xmp.codeUnits];
  final len = payload.length + 2;
  return [0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF, ...payload];
}

/// Mirrors add_content_screen.dart:470-475 exactly: the scrubbed bytes
/// are adopted ONLY when wasModified reports field removals.
Uint8List _shippedBytes(Uint8List input, ScrubbingResult result) =>
    result.wasModified ? result.scrubbedBytes : input;

void main() {
  final svc = MetadataScrubbingService(CidService());

  test('a COM-only JPEG ships its comment even with strip-metadata on',
      () async {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      ..._jfifApp0,
      ..._comSegment('Shot on personal phone, home GPS 37.7749,-122.4194'),
      ..._sosAndScan,
    ]);

    final result = await svc.scrubMetadata(jpeg);

    // The scrubber DID drop the COM segment - the clean output exists.
    expect(result.scrubbedBytes.length, lessThan(jpeg.length));
    expect(
        result.scrubbedBytes
            .join(',')
            .contains('71,80,83'), // 'GPS' - COM payload bytes
        isFalse,
        reason: 'sanity: COM payload is genuinely gone from scrubbedBytes');

    // …but the caller contract says "unmodified" because the exif
    // detector could not see a COM - so the UI keeps the ORIGINAL.
    final shipped = _shippedBytes(jpeg, result);
    expect(shipped.join(',').contains('71,80,83'), isFalse,
        reason: 'wasModified==false makes add_content_screen keep the '
            'original bytes — the COM comment ships despite the '
            'user-enabled metadata strip.');
  });

  test('an XMP-only APP1 JPEG ships its XMP packet untouched', () async {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      ..._jfifApp0,
      ..._xmpApp1('<x:xmpmeta><dc:creator>Eve Private</dc:creator>'
          '</x:xmpmeta>'),
      ..._sosAndScan,
    ]);

    final result = await svc.scrubMetadata(jpeg);
    // APP1 is unconditionally stripped - clean output exists.
    expect(result.scrubbedBytes.length, lessThan(jpeg.length));

    final shipped = _shippedBytes(jpeg, result);
    expect(
        shipped
            .join(',')
            .contains('69,118,101'), // 'Eve' survives → gate failed
        isFalse,
        reason: 'an XMP packet with no Exif header is invisible to the '
            'detector: wanted=={} → wasModified==false → the UI ships '
            'the original file with the author field intact.');
  });
}
