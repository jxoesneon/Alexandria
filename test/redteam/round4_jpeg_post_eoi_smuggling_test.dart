// RED TEAM PoC - Round-4: the round-3 fix dropped bytes after PNG's
// IEND ("bytes after IEND are NOT part of the PNG stream - ancillary
// chunks smuggled past the terminator rode through verbatim"). The JPEG
// walker has the SAME hole left open: on EOI (0xFFD9) it copies the
// marker AND everything after verbatim -
//
//   lib/services/metadata_scrubbing_service.dart:304-306
//     if (marker == 0xD9 || marker == 0xDA) {
//       out.add(bytes.sublist(segStart));   // ← includes post-EOI tail
//       break;
//     }
//
// SOS needs the verbatim copy (entropy data follows it), but EOI is the
// END of the stream - nothing after 0xFFD9 is image data. Arbitrary
// payload appended post-EOI survives "scrubbing", exactly the covert
// channel the PNG fix closed.
//
// Asserts the SECURE expectation: post-terminator bytes are dropped for
// JPEG exactly as they are for PNG.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';

void main() {
  final svc = MetadataScrubbingService(CidService());

  test('bytes appended after JPEG EOI (0xFFD9) must be dropped', () async {
    final tail = Uint8List.fromList('POST-EOI-COVERT-PAYLOAD'.codeUnits);
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      0xFF, 0xE1, 0x00, 0x10, // APP1, len=16 (covers len bytes + 14 data)
      ...'Exif'.codeUnits, 0x00, 0x00,
      ...List.filled(8, 0x41), // padding to fill the declared segment
      0xFF, 0xD9, // EOI - end of image stream
      ...tail, // smuggled tail - not part of the image
    ]);

    final result = await svc.scrubMetadata(jpeg);
    expect(result.scrubbedBytes, isNot(contains(tail.first)),
        reason: 'a payload appended after the JPEG EOI marker survived '
            'scrubbing verbatim — the same covert channel the round-3 '
            'fix closed for post-IEND PNG data is still open post-EOI '
            'for JPEG. EOI terminates the stream; trailing bytes are '
            'smuggling, not image data.');
  });

  test('post-IEND PNG smuggling stays closed (verification)', () async {
    final tail = 'SMUGGLED'.codeUnits;
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
      // IHDR chunk: len=13, type IHDR, 13 zero bytes, 4 CRC bytes
      0x00, 0x00, 0x00, 0x0D, ...'IHDR'.codeUnits,
      ...List.filled(13, 0), ...List.filled(4, 0),
      // IEND chunk: len=0, type IEND, 4 CRC bytes
      0x00, 0x00, 0x00, 0x00, ...'IEND'.codeUnits,
      ...List.filled(4, 0),
      ...tail,
    ]);
    final result = await svc.scrubMetadata(png);
    expect(result.scrubbedBytes.length, png.length - tail.length);
  });
}
