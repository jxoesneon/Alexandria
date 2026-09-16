// RED TEAM PoC — Round-7: scrubMetadata crashes outright on malformed
// images — the exif-3.3.0 reader is invoked UNGUARDED.
//
//   lib/services/metadata_scrubbing_service.dart
//     :229   final data = await readExifFromBytes(bytes);          // input
//     :252   final remaining = await readExifFromBytes(scrubbedBytes); // output
//
// extractMetadata() (:189) and detectSensitiveFields() (:200) both wrap
// the same call in try/catch — scrubMetadata does not. The exif reader
// throws RangeError on truncated PNG chunk headers
// (read_exif.dart:370 `data.sublist(4, 8)` after a short readSync) and
// on degenerate JPEG streams (:239 `listRangeEqual`/`sublist` past EOF
// is only partially caught — `_incrementBase` is guarded, the
// `listRangeEqual` calls are not).
//
// Impact path: add_content_screen.dart:472 — a user with "strip
// metadata" enabled who picks a truncated/corrupt-but-sniffable image
// gets `Error: RangeError…` and the upload aborts entirely. Privacy
// fails closed (nothing ships), but the API contract and UX are
// broken, and — critically — it MASKS the PNG verbatim-tail issue:
// once this crash is fixed the tail-copy becomes reachable.
//
// Asserts the SECURE expectation: scrubMetadata must never throw on
// malformed input; it either scrubs or returns the input unmodified
// with honest (empty) claims.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';

const _pngSig = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

List<int> _chunk(String type, List<int> data) => [
      (data.length >> 24) & 0xFF,
      (data.length >> 16) & 0xFF,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
      ...type.codeUnits,
      ...data,
      0, 0, 0, 0,
    ];

void main() {
  final svc = MetadataScrubbingService(CidService());

  test('truncated PNG (partial chunk header) must not throw', () async {
    final png = Uint8List.fromList([
      ..._pngSig,
      ..._chunk('IHDR', List.filled(13, 1)),
      0x00, 0x00, 0x00, 0x04, 0x74, 0x45, 0x58, // truncated 'tEX…' header
    ]);
    expect(() => svc.scrubMetadata(png), returnsNormally,
        reason:
            'readExifFromBytes throws RangeError on a partial PNG chunk '
            'header — the call at :229 is unguarded.');
  });

  test('PNG with an overrun chunk length must not throw', () async {
    final png = Uint8List.fromList([
      ..._pngSig,
      ..._chunk('IHDR', List.filled(13, 1)),
      0x7F, 0xFF, 0xFF, 0xFF, ...'IDAT'.codeUnits, 0x11, 0x22,
      ..._chunk('IEND', const []),
    ]);
    expect(() => svc.scrubMetadata(png), returnsNormally,
        reason:
            'the reader seeks chunkSize+4 past EOF and its next 8-byte '
            'header read throws — unguarded at :229.');
  });

  test('degenerate JPEG produced by the scrubber itself must not crash '
      'the verification pass', () async {
    // A stream that scrubs down to SOI + APP0 + EOI (everything else
    // malformed): the round-6 walker emits exactly that — then the
    // :252 verification read throws inside _jpegReadParams.
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      0xFF, 0xE0, 0x00, 0x10, // APP0 JFIF
      0x4A, 0x46, 0x49, 0x46, 0x00,
      0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
      0x77, 0x66, // non-marker garbage → resync…
      0xFF, 0xD9, // …onto a bare EOI → stream ends
      0xFF, 0xE1, 0x00, 0x10, ...'Exif\x00\x00'.codeUnits, // post-EOI
    ]);
    expect(() => svc.scrubMetadata(jpeg), returnsNormally,
        reason:
            'the scrubbed SOI+APP0+EOI output crashes readExifFromBytes '
            'at :252 — the scrubber\'s own output is unhandled input.');
  });
}
