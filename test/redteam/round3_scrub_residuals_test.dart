// RED TEAM PoC — MetadataScrubbingService residuals.
//
// GAP 1 — isSupportedType overclaims. The scrub switch in
// scrubMetadata (lib/services/metadata_scrubbing_service.dart:238-248)
// handles ONLY image/jpeg and image/png; every other MIME falls into
// `default:` and returns the input byte-identical. Yet isSupportedType
// (lines 418-425) advertises 'image/heic', 'image/heif' and
// 'image/tiff' as scrubbable. The add-content flow
// (lib/ui/add_content_screen.dart:471) gates on isSupportedType, so a
// user who enables "strip metadata" on a HEIC gets a byte-identical
// upload — GPS/Make/Model intact — under a "supported" promise.
//
// GAP 2 — post-IEND PNG tail. _stripPngMetadataChunks copies any bytes
// after IEND verbatim (lines 366-369). A tEXt/eXIf chunk appended after
// the IEND terminator rides straight through the "scrubbed" output —
// a metadata smuggling channel the stripper neither removes nor flags.
//
// Asserts the SECURE expectation: only formats that are actually
// stripped may be advertised, and the scrubbed byte stream must not
// still carry strippable metadata chunks.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';

void main() {
  final svc = MetadataScrubbingService(CidService());

  test('isSupportedType must not claim formats the scrubber passes '
      'through unchanged', () async {
    for (final mime in ['image/heic', 'image/heif', 'image/tiff']) {
      expect(svc.isSupportedType(mime), isFalse,
          reason:
              'isSupportedType("$mime") advertises scrub support, but '
              'scrubMetadata has no handler for it — the user\'s '
              '"strip metadata" choice silently produces a byte-'
              'identical upload with all metadata intact.');
    }
  });

  test('metadata chunks appended after PNG IEND must not survive the '
      'scrub', () async {
    const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    Uint8List chunk(String type, List<int> data) {
      final out = BytesBuilder()
        ..add([
          (data.length >> 24) & 0xFF,
          (data.length >> 16) & 0xFF,
          (data.length >> 8) & 0xFF,
          data.length & 0xFF
        ])
        ..add(type.codeUnits)
        ..add(data)
        ..add([0, 0, 0, 0]); // (bogus CRC — irrelevant to the walker)
      return out.toBytes();
    }

    final png = BytesBuilder()
      ..add(sig)
      ..add(chunk('IHDR', List.filled(13, 0)))
      ..add(chunk('IEND', const []))
      // Smuggled tail: a tEXt chunk AFTER the IEND terminator.
      ..add(chunk('tEXt',
          'GPS\x00lat 51.5 lon -0.12; device SerialNo-1234'.codeUnits));
    final input = png.toBytes();

    final result = await svc.scrubMetadata(input);
    final outStr = String.fromCharCodes(result.scrubbedBytes);
    expect(outStr.contains('tEXt'), isFalse,
        reason:
            'a tEXt chunk appended after IEND survives verbatim in the '
            '"scrubbed" output — post-terminator bytes are copied '
            'uninspected, so metadata smuggled past the terminator is '
            'neither stripped nor reported.');
    expect(outStr.contains('SerialNo-1234'), isFalse);
  });
}
