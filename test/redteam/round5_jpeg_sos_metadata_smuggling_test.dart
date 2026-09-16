// RED TEAM PoC — Round-5: the round-4 "post-EOI drop" fix for JPEG is
// vacuous for every REAL JPEG. The marker walker terminates on EOI only
// when EOI is reached INSIDE the marker loop — but a real JPEG always
// hits SOS (0xFFDA) first, and the SOS branch copies
// `bytes.sublist(segStart)` — everything from the SOS marker to EOF —
// verbatim:
//
//   lib/services/metadata_scrubbing_service.dart:301-307
//     if (marker == 0xDA) {
//       out.add(bytes.sublist(segStart));   // ← SOS .. EOF, incl. post-EOI
//       break;
//     }
//
// The round-4 fixture (test/redteam/round4_jpeg_post_eoi_smuggling_test)
// is a degenerate SOI+APP1+EOI image with NO scan — the only shape that
// ever reaches the EOI branch. Two consequences stay open:
//
//   1. post-EOI tail: `SOI … SOS <entropy> EOI <payload>` — the payload
//      is not image data yet ships in scrubbedBytes (the exact covert
//      channel the round-4 fix claimed to close).
//   2. post-SOS APP/COM segments: multi-scan (progressive) JPEGs
//      legitimately interleave markers between scans, so an APP1/Exif
//      or COM segment placed after the first SOS is *inside* the
//      declared stream — it survives "scrubbing" untouched, and if the
//      EXIF parser doesn't scan past SOS it isn't even reported.
//
// Asserts the SECURE expectation: nothing after EOI is emitted, and no
// APP1/COM segment survives anywhere in the stream.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';

void main() {
  final svc = MetadataScrubbingService(CidService());

  test('post-EOI payload survives when the JPEG carries a real SOS scan',
      () async {
    final tail = Uint8List.fromList('POST-EOI-COVERT-PAYLOAD'.codeUnits);
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      // SOS marker, length=8 (len bytes + 6-byte minimal scan header)
      0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
      // entropy-coded data with byte-stuffed 0xFF00 (not a marker)
      0x11, 0x22, 0xFF, 0x00, 0x33, 0x44,
      0xFF, 0xD9, // EOI — end of image stream
      ...tail, // smuggled tail — must never be emitted
    ]);

    final result = await svc.scrubMetadata(jpeg);
    final scrubbed = result.scrubbedBytes;

    // Locate EOI in the output; nothing may follow it.
    var eoiIndex = -1;
    for (var i = 0; i + 1 < scrubbed.length; i++) {
      if (scrubbed[i] == 0xFF && scrubbed[i + 1] == 0xD9) {
        eoiIndex = i;
      }
    }
    expect(eoiIndex, isNonNegative,
        reason: 'the scrubbed JPEG must retain its EOI terminator');
    expect(scrubbed.length, eoiIndex + 2,
        reason:
            'bytes appended after JPEG EOI survived scrubbing: the SOS '
            'branch copies sublist(segStart) → EOF verbatim, so the '
            'round-4 EOI fix never runs for any JPEG that actually has '
            'a scan — the post-EOI covert channel is still open.');
  });

  test('an APP1 segment placed after SOS (multi-scan JPEG) is stripped',
      () async {
    // Progressive/multi-scan JPEGs legitimately interleave markers
    // between scans — so APPn/COM after the first SOS is *in-stream*
    // metadata, not trailing garbage. It must be dropped too.
    final exif = Uint8List.fromList([
      ...'Exif'.codeUnits, 0x00, 0x00,
      ...'GPS-COVER-T-42.0,-71.0'.codeUnits,
    ]);
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      // First SOS + first scan's entropy data
      0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
      0x11, 0x22, 0xFF, 0x00, 0x33, // stuffed-FF entropy bytes
      // Second scan's header segments begin — attacker hides APP1 here
      0xFF, 0xE1, ((exif.length + 2) >> 8) & 0xFF, (exif.length + 2) & 0xFF,
      ...exif,
      // Second SOS + remainder + EOI
      0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
      0x55, 0x66,
      0xFF, 0xD9,
    ]);

    final result = await svc.scrubMetadata(jpeg);
    final scrubbed = result.scrubbedBytes;

    // No APP1 marker may survive anywhere in the output stream.
    var app1Present = false;
    for (var i = 0; i + 1 < scrubbed.length; i++) {
      if (scrubbed[i] == 0xFF && scrubbed[i + 1] == 0xE1) {
        app1Present = true;
      }
    }
    expect(app1Present, isFalse,
        reason:
            'an APP1/Exif segment placed after the first SOS marker '
            'survived scrubbing — the verbatim sublist(segStart)→EOF '
            'copy preserves every post-SOS metadata segment, so '
            'multi-scan JPEGs smuggle EXIF/GPS through the "scrubbed" '
            'output.');
  });
}
