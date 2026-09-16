// RED TEAM PoC - Round-7: the PNG scrubber kept the exact fail-open
// tail the round-6 fix removed from the JPEG walker.
//
//   lib/services/metadata_scrubbing_service.dart:445-456
//     final end = i + 12 + len;
//     if (len < 0 || end > bytes.length) {
//       // Malformed chunk - copy the rest verbatim and stop.
//       out.add(bytes.sublist(i));              // ← VERBATIM TAIL
//       return out.toBytes();
//     }
//
// A chunk whose declared length overruns the file makes the walker
// copy EVERYTHING after it - including complete, well-formed eXIf /
// tEXt / iTXt chunks placed behind the fault - into `scrubbedBytes`.
// That is precisely the smuggle the round-6 JPEG fix closed by
// resyncing forward and DROPPING the unparseable region; the PNG side
// still ships it. (The in-code comment claims the tail "cannot be
// re-chunked safely" - but dropping it, or resyncing onto a
// CRC-validated chunk header, is strictly safer for the privacy goal
// than copying attacker bytes verbatim, and the output is already a
// degraded stream either way.)
//
// Asserts the SECURE expectation: no 'eXIf'/'tEXt' chunk signature may
// survive in the scrubbed output, wherever the malformed chunk sits.
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
      0, 0, 0, 0, // CRC - the scrubber does not verify it
    ];

bool _containsAscii(Uint8List bytes, String needle) {
  final n = needle.codeUnits;
  outer:
  for (var i = 0; i + n.length <= bytes.length; i++) {
    for (var k = 0; k < n.length; k++) {
      if (bytes[i + k] != n[k]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  final svc = MetadataScrubbingService(CidService());

  test('an eXIf chunk behind a malformed-length chunk survives verbatim',
      () async {
    final png = Uint8List.fromList([
      ..._pngSig,
      ..._chunk('IHDR', List.filled(13, 1)),
      // Malformed chunk: declares ~2 GiB - `end` overruns the file and
      // the walker copies the whole rest of the stream verbatim.
      0x7F, 0xFF, 0xFF, 0xFF, ...'IDAT'.codeUnits, 0x11, 0x22,
      // A complete, well-formed eXIf chunk carrying a TIFF header -
      // the privacy payload the scrubber exists to remove.
      ..._chunk('eXIf', [...'II*\x00'.codeUnits, ...List.filled(32, 0xAA)]),
      ..._chunk('tEXt', 'Author\x00Eve Private'.codeUnits),
      ..._chunk('IEND', const []),
    ]);

    // NOTE: today the UNGUARDED readExifFromBytes call at :229 throws
    // RangeError on this stream before the strip runs (see
    // round7_scrub_unhandled_exceptions_test.dart). The latent bug
    // underneath: once that call is guarded, the verbatim-tail branch
    // ships the eXIf/tEXt chunks below untouched. Both assertions must
    // hold for the fix to be complete.
    ScrubbingResult? result;
    try {
      result = await svc.scrubMetadata(png);
    } catch (_) {
      fail('scrubMetadata threw on malformed PNG instead of failing '
          'closed gracefully');
    }
    expect(_containsAscii(result.scrubbedBytes, 'eXIf'), isFalse,
        reason: 'malformed-chunk bail-out copies the tail verbatim — a '
            'complete eXIf chunk survives in "scrubbed" output.');
    expect(_containsAscii(result.scrubbedBytes, 'tEXt'), isFalse,
        reason: 'a tEXt chunk behind the malformed chunk survives too.');
    expect(_containsAscii(result.scrubbedBytes, 'Eve Private'), isFalse);
  });

  test(
      'an iCCP chunk (ICC profile carrying author/copyright strings) '
      'is retained by the scrubber', () async {
    // ICC profiles embed 'desc' (profile description - routinely a
    // tool/author string) and 'cprt' (copyright) tags; exiftool-class
    // extractors surface them. iCCP is ancillary - dropping it can
    // never break decode - yet it is absent from _pngStrippedChunks.
    final png = Uint8List.fromList([
      ..._pngSig,
      ..._chunk('IHDR', List.filled(13, 1)),
      ..._chunk(
          'iCCP',
          'Personal Profile\x00\x00cprtCopyright Eve Private descHome studio'
              .codeUnits),
      ..._chunk('IDAT', List.filled(16, 0x42)),
      ..._chunk('IEND', const []),
    ]);

    final result = await svc.scrubMetadata(png);
    expect(
        _containsAscii(result.scrubbedBytes, 'Copyright Eve Private'), isFalse,
        reason: 'iCCP is not in _pngStrippedChunks — embedded author/'
            'copyright strings survive every scrub.');
  });
}
