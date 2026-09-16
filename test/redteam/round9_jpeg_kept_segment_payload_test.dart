// RED TEAM PoC - Round-9: the round-8 fix made the APPn class
// fail-closed at the *marker* level (_jpegStrippedMarkers now covers
// 0xE1-0xEF except 0xE0/0xEE, plus COM), but the keep-dispatch
// inspects ONLY the marker byte. Every kept segment is emitted as
// `sublist(segStart, i + 2 + segLen)` - its declared-length payload is
// copied verbatim and never content-checked:
//
//   lib/services/metadata_scrubbing_service.dart:494-496
//     if (!_jpegStrippedMarkers.contains(marker)) {
//       out.add(bytes.sublist(segStart, i + 2 + segLen));
//     }
//
// That leaves a metadata carrier the APPn denylist cannot see:
//
//   1. JFXX (JFIF extension) APP0 - a *second* APP0 whose payload is
//      'JFXX\0' || ext-code. Extension 0x10 is defined by the JFIF
//      spec as a JPEG-ENCODED thumbnail: a complete FF D8 … FF D9
//      stream with its own marker surface, including its own APP1/Exif
//      with GPS. The marker byte is 0xE0 → kept verbatim → the inner
//      EXIF rides through. Worse, package:exif's segment walker
//      (_incrementBase jumps by declared length) never looks inside an
//      APP0 payload, so the post-scrub verification pass reports the
//      outer fields "genuinely gone" and removedFields CLAIMS their
//      removal while byte-identical EXIF/GPS ships inside the kept
//      segment - the round-2 claims-vs-reality class, through a
//      standards-defined carrier.
//
//   2. APP14 (0xEE) - kept "for the Adobe color transform", but the
//      keep is unbounded and unsigned: an APP14 with a bogus signature
//      and a 60 KB payload ships a full EXIF block verbatim. Only a
//      canonical 'Adobe' 14-byte segment is decode-relevant; anything
//      else is a covert channel.
//
//   3. The rest of the marker space - reserved JPGn (0xF0-0xFD),
//      unassigned 0x02-0xBF - is not in the strip set either. The
//      dispatch is a denylist, not a decode-relevant allowlist, so a
//      reserved marker's payload is a verbatim byte channel.
//
//   4. The round-6 resync path re-dispatches through the same keep
//      check, so an attacker-placed `FF F0 <len> <EXIF>` behind a
//      corrupt segment is resynced ONTO and then emitted verbatim -
//      the resync re-validates the strip set but still trusts the
//      kept marker's payload.
//
// Asserts the SECURE expectation (same criterion as round-6): no
// `FF E1 <len> 'Exif'` byte pattern may survive ANYWHERE in the
// scrubbed output, and removedFields may not claim a field whose bytes
// still ship.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';
import '../fixtures/exif_fixture_generator.dart';

List<int> _seg(int marker, List<int> payload) {
  final len = payload.length + 2;
  return [0xFF, marker, (len >> 8) & 0xFF, len & 0xFF, ...payload];
}

/// Complete `FF E1 <len> Exif…` APP1 segment out of the fixture JPEG.
Uint8List _exifApp1Segment() {
  final jpeg = buildSampleExifJpeg();
  final segLen = (jpeg[4] << 8) | jpeg[5];
  return Uint8List.fromList(jpeg.sublist(2, 2 + 2 + segLen));
}

/// Counts `FF E1 ?? ?? 'Exif'` APP1-bearing patterns anywhere in the
/// byte stream - the same survival criterion round-6 established.
int _countExifMarkers(Uint8List bytes) {
  var count = 0;
  for (var i = 0; i + 7 < bytes.length; i++) {
    if (bytes[i] == 0xFF &&
        bytes[i + 1] == 0xE1 &&
        bytes[i + 4] == 0x45 && // 'E'
        bytes[i + 5] == 0x78 && // 'x'
        bytes[i + 6] == 0x69 && // 'i'
        bytes[i + 7] == 0x66) {
      count++;
    }
  }
  return count;
}

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

const _jfifApp0 = <int>[
  0xFF, 0xE0, 0x00, 0x10, // APP0, length 16
  0x4A, 0x46, 0x49, 0x46, 0x00, // 'JFIF\0'
  0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
];

void main() {
  final svc = MetadataScrubbingService(CidService());

  test(
      'JFXX APP0 embeds a complete JPEG thumbnail whose own EXIF/GPS '
      'rides through the scrubber — and is claimed removed', () async {
    final innerApp1 = _exifApp1Segment();
    // Inner thumbnail: a complete JPEG stream (JFIF-spec extension
    // 0x10 = "thumbnail coded using JPEG") carrying its own Exif APP1.
    final innerJpeg =
        Uint8List.fromList([0xFF, 0xD8, ...innerApp1, 0xFF, 0xD9]);
    final jfxxApp0 = _seg(0xE0, [
      ...'JFXX\x00'.codeUnits,
      0x10, // extension code: JPEG-encoded thumbnail
      ...innerJpeg,
    ]);
    final outer = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      ..._jfifApp0,
      ...innerApp1, // outer APP1 - detected, stripped, CLAIMED removed
      ...jfxxApp0, // JFXX APP0 - kept verbatim, inner EXIF survives
      0xFF, 0xD9, // EOI
    ]);

    // Sanity: the scrub actually runs and claims fields.
    expect(await svc.detectSensitiveFields(outer), isNotEmpty);

    final result =
        await svc.scrubMetadata(outer, options: ScrubbingOptions.full);

    expect(_countExifMarkers(result.scrubbedBytes), 0,
        reason: 'the JFXX APP0 marker byte (0xE0) is in the keep set, '
            'so its payload — a complete inner JPEG with its own '
            'Exif/GPS APP1 — is copied verbatim. The scrubber does not '
            'recurse into kept-segment payloads.');
    expect(_containsAscii(result.scrubbedBytes, 'Sony'), isFalse,
        reason: 'inner-thumbnail TIFF data (Make=Sony) ships verbatim.');
    // The verification pass cannot see inside APP0 either, so
    // removedFields may claim the very fields still shipping.
    if (result.removedFields.isNotEmpty) {
      expect(_containsAscii(result.scrubbedBytes, 'Exif'), isFalse,
          reason: 'removedFields=${result.removedFields} claims '
              'removal while an Exif block survives inside the kept '
              'JFXX thumbnail — false "removed" claim.');
    }
  });

  test(
      'APP14 keep is unbounded: non-Adobe / oversized APP14 payload '
      'carries an EXIF block verbatim', () async {
    final app14 = _seg(0xEE, [
      // Bogus signature - not 'Adobe'. Even with a valid Adobe prefix,
      // payload beyond the canonical 12-byte transform record is
      // uninspected trailer space.
      ...'ExifStash'.codeUnits,
      0x00, 0x01,
      ..._exifApp1Segment(),
    ]);
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      ..._exifApp1Segment(), // real APP1 - stripped
      ...app14,
      0xFF, 0xD9,
    ]);

    final result =
        await svc.scrubMetadata(jpeg, options: ScrubbingOptions.full);
    expect(_countExifMarkers(result.scrubbedBytes), 0,
        reason: '0xEE is kept without checking the Adobe signature or '
            'bounding the segment to its canonical length — arbitrary '
            'APP14 payload is a verbatim metadata channel.');
  });

  test(
      'reserved JPGn marker (0xF0) payload carries EXIF verbatim — '
      'the dispatch is a denylist, not a decode-relevant allowlist', () async {
    final reserved = _seg(0xF0, _exifApp1Segment());
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      ..._exifApp1Segment(), // real APP1 - stripped
      ...reserved,
      0xFF, 0xD9,
    ]);

    final result =
        await svc.scrubMetadata(jpeg, options: ScrubbingOptions.full);
    expect(_countExifMarkers(result.scrubbedBytes), 0,
        reason: '0xF0 (JPGn/reserved) is not in _jpegStrippedMarkers '
            'and not a standalone marker, so its declared-length '
            'payload is emitted verbatim — the round-8 fix closed the '
            'APPn class but the keep-rule still trusts every other '
            'marker payload.');
  });

  test(
      'resync path: a fake kept-marker behind a corrupt segment is '
      'resynced onto and its EXIF payload emitted verbatim', () async {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      ..._exifApp1Segment(), // APP1#1 - stripped
      // Corrupt APP2: declared length overruns the file → resync.
      0xFF, 0xE2, 0xFF, 0xFF, 0x49, 0x43, 0x43,
      // Resync lands here: reserved marker whose payload is a full
      // Exif APP1 - emitted verbatim through the keep path.
      ..._seg(0xF0, _exifApp1Segment()),
      0xFF, 0xD9,
    ]);

    final result =
        await svc.scrubMetadata(jpeg, options: ScrubbingOptions.full);
    expect(_countExifMarkers(result.scrubbedBytes), 0,
        reason: '_nextJpegMarker repositions onto the attacker-placed '
            'FF F0; the normal dispatch then emits its payload '
            'verbatim — resync validates the strip set but never the '
            'kept segment\'s contents.');
  });
}
