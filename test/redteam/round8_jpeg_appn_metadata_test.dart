// RED TEAM PoC - Round-8: the round-7 fix added 'iCCP' to the PNG
// strip set because ICC profiles embed 'desc'/'cprt' author/copyright
// strings readable by exiftool-class extractors. The IDENTICAL carrier
// in JPEG - APP2 (0xE2) segments signed "ICC_PROFILE\0" (chunked per
// ICC.1: seq + count bytes after the signature) - is NOT in
// _jpegStrippedMarkers:
//
//   lib/services/metadata_scrubbing_service.dart:335
//     static const Set<int> _jpegStrippedMarkers = {0xE1, 0xED, 0xFE};
//
// APP2 is copied verbatim by the marker walker, so a JPEG carrying an
// ICC profile ships its 'desc'/'cprt' strings through every scrub.
// Worse, the exif reader does not parse ICC at all, so
// detectSensitiveFields() returns [] and the UI shows the user
// "No sensitive fields detected - already clean" while the file
// carries identifying text; bytesChanged is false so the ORIGINAL
// bytes ship (complete fail-open for this carrier class).
//
// Same class: APP12 (0xEC) 'Ducky'/'PictureInfo' (Photoshop "Save for
// Web" copyright/comment blocks) and APP3 (0xE3) 'Meta'/'Exif'
// variants also pass through verbatim. The fail-closed fix is to drop
// every APPn not required for decode (keep APP0 JFIF and APP14 Adobe),
// or at minimum add 0xE2/0xEC/0xE3 to the strip set - matching the
// privacy posture already taken for PNG ancillary chunks.
//
// Asserts the SECURE expectation: no 'ICC_PROFILE' signature, 'cprt'
// copyright string, or 'Ducky' block may survive in scrubbed output.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';

List<int> _seg(int marker, List<int> payload) {
  final len = payload.length + 2;
  return [0xFF, marker, (len >> 8) & 0xFF, len & 0xFF, ...payload];
}

final _jfif = _seg(0xE0, [
  ...'JFIF\x00'.codeUnits,
  0x01,
  0x02,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
]);

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

  test(
      'an APP2 ICC_PROFILE segment (desc/cprt strings) survives '
      'scrubbing verbatim', () async {
    final icc = [
      ...'ICC_PROFILE\x00'.codeUnits,
      0x01, 0x01, // chunk 1 of 1
      ...'....cprtCopyright Eve Private....descHome studio rig'.codeUnits,
    ];
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      ..._jfif,
      ..._seg(0xE2, icc), // APP2 - ICC profile, not stripped today
      0xFF, 0xD9, // EOI
    ]);

    final detected = await svc.detectSensitiveFields(jpeg);
    // Detector blindness is part of the finding: the UI reports this
    // file "already clean" while it carries copyright/author text.
    expect(detected, isEmpty,
        reason: 'exif reader cannot see ICC — confirms the UI '
            '"already clean" claim is made for an unclean file.');

    final result = await svc.scrubMetadata(jpeg);
    expect(_containsAscii(result.scrubbedBytes, 'ICC_PROFILE'), isFalse,
        reason: 'APP2 is absent from _jpegStrippedMarkers — the ICC '
            'profile (with cprt/desc strings) is copied verbatim.');
    expect(
        _containsAscii(result.scrubbedBytes, 'Copyright Eve Private'), isFalse);
  });

  test(
      'an APP2 ICC behind a corrupt segment still survives via the '
      'round-6 resync path', () async {
    // The resync walker DROPS corrupt regions but then re-parses the
    // next marker - APP2 arrives cleanly at a segment boundary and is
    // emitted verbatim. Fail-closed resync is not enough while 0xE2 is
    // absent from the strip set.
    final icc = [
      ...'ICC_PROFILE\x00'.codeUnits,
      0x01,
      0x01,
      ...'cprtStudioOwner'.codeUnits,
    ];
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfif,
      // Corrupt DQT: declares a length that overruns the file.
      0xFF, 0xDB, 0x7F, 0xFF, 0x99, 0x88,
      ..._seg(0xE2, icc),
      0xFF, 0xD9,
    ]);

    final result = await svc.scrubMetadata(jpeg);
    expect(_containsAscii(result.scrubbedBytes, 'ICC_PROFILE'), isFalse,
        reason: 'resync lands on the APP2 marker, which is then copied '
            'verbatim because 0xE2 is not stripped.');
  });

  test(
      'an APP12 Ducky/PictureInfo block (Save-for-Web copyright) '
      'survives verbatim', () async {
    final ducky = [
      ...'Ducky\x00'.codeUnits,
      // <tag=2 copyright><len><text>
      0x00, 0x02, 0x00, 0x0D,
      ...'PrivateOwner!'.codeUnits,
      0x00, 0x00,
    ];
    final jpeg = Uint8List.fromList([
      0xFF,
      0xD8,
      ..._jfif,
      ..._seg(0xEC, ducky),
      0xFF,
      0xD9,
    ]);

    final result = await svc.scrubMetadata(jpeg);
    expect(_containsAscii(result.scrubbedBytes, 'PrivateOwner!'), isFalse,
        reason: 'APP12 (Ducky/PictureInfo copyright carrier) is not '
            'stripped — same class as APP2.');
  });
}
