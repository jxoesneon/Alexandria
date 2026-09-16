// RED TEAM verification - Round-7: adversarial stress of the round-6
// JPEG resync. Each case tries to route a COMPLETE, parseable APP1
// segment past _nextJpegMarker / the resync paths. All asserts are the
// SECURE expectation - these are expected to PASS; a failure is a live
// resync bypass.
//
//   lib/services/metadata_scrubbing_service.dart:296-425
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';
import '../fixtures/exif_fixture_generator.dart';

/// Extracts the complete `FF E1 <len> Exif…` APP1 segment out of the
/// fixture JPEG (SOI ‖ APP1 ‖ EOI).
Uint8List _exifApp1Segment() {
  final jpeg = buildSampleExifJpeg();
  final segLen = (jpeg[4] << 8) | jpeg[5];
  return Uint8List.fromList(jpeg.sublist(2, 2 + 2 + segLen));
}

/// Counts byte-level 'FF E1 ?? ?? Exif' APP1 signatures anywhere in the
/// output - including inside copied segment payloads.
int _countExifSignatures(Uint8List bytes) {
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

/// Walks the OUTPUT stream the way a strict decoder does and returns
/// the count of APP1 segments found at real segment boundaries (not
/// inside copied payload).
int _countParseableApp1(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 0;
  var count = 0;
  var i = 2;
  var inEntropy = false;
  while (i + 1 < bytes.length) {
    if (inEntropy) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final next = bytes[i + 1];
      if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
        i += 2;
        continue;
      }
      inEntropy = false;
      continue;
    }
    if (bytes[i] != 0xFF) return count; // malformed - decoder bails
    while (i + 1 < bytes.length && bytes[i + 1] == 0xFF) {
      i++;
    }
    if (i + 1 >= bytes.length) return count;
    final marker = bytes[i + 1];
    if (marker == 0xD9) return count; // EOI
    if (marker == 0x00) return count;
    if (marker == 0x01 ||
        marker == 0xD8 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (i + 4 > bytes.length) return count;
    final len = (bytes[i + 2] << 8) | bytes[i + 3];
    if (len < 2 || i + 2 + len > bytes.length) return count;
    if (marker == 0xE1) count++;
    i += 2 + len;
    if (marker == 0xDA) inEntropy = true;
  }
  return count;
}

const _jfifApp0 = <int>[
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0x02,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
];

const _sosAndScan = <int>[
  0xFF,
  0xDA,
  0x00,
  0x08,
  0x01,
  0x01,
  0x00,
  0x00,
  0x3F,
  0x00,
  0x11,
  0x22,
  0xFF,
  0x00,
  0x33,
  0xFF,
  0xD9,
];

void main() {
  final svc = MetadataScrubbingService(CidService());

  test(
      'APP1 whose marker bytes are consumed as a corrupt length word '
      'still gets stripped at the NEXT boundary', () async {
    final app1 = _exifApp1Segment();
    // 'FF DB' + length bytes 'FF E1' → segLen 0xFFE1 (huge, malformed).
    // Resync starts at i+4, skipping the consumed E1 - the hidden APP1
    // that follows must still be found and dropped.
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      0xFF, 0xDB, 0xFF, 0xE1, // DQT with corrupt length (eats FF E1)
      ...app1, // real, complete APP1/Exif
      ..._sosAndScan,
    ]);
    final result = await svc.scrubMetadata(jpeg);
    expect(_countExifSignatures(result.scrubbedBytes), 0);
    expect(_countParseableApp1(result.scrubbedBytes), 0);
  });

  test('a nested APP1 inside a corrupt-length outer APP1 is stripped',
      () async {
    final app1 = _exifApp1Segment();
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      // Outer APP1 with a corrupt (overrun) length; inside its would-be
      // payload sits a complete inner APP1.
      0xFF, 0xE1, 0xFF, 0xFE, 0x41, 0x42,
      ...app1,
      ..._sosAndScan,
    ]);
    final result = await svc.scrubMetadata(jpeg);
    expect(_countExifSignatures(result.scrubbedBytes), 0);
  });

  test(
      'APP1 reached through 0xFF fill bytes inside a corrupt region is '
      'stripped', () async {
    final app1 = _exifApp1Segment();
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      0x99, // non-marker byte → resync
      0xFF, 0xFF, 0xFF, // fill 0xFFs directly before the hidden marker
      ...app1,
      ..._sosAndScan,
    ]);
    final result = await svc.scrubMetadata(jpeg);
    expect(_countExifSignatures(result.scrubbedBytes), 0);
  });

  test(
      'APP1 placed mid-scan (inside entropy-coded data after SOS) is '
      'treated as a marker boundary and stripped', () async {
    final app1 = _exifApp1Segment();
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      // SOS header then scan data containing stuffed FFs and a restart
      // marker before the smuggled APP1.
      0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F, 0x00,
      0x11, 0xFF, 0x00, 0x22, 0xFF, 0xD0, 0x33, // stuffed + RST0
      ...app1, // APP1 inside the entropy-coded stream
      0x44, 0x55,
      0xFF, 0xD9, // EOI
    ]);
    final result = await svc.scrubMetadata(jpeg);
    expect(_countExifSignatures(result.scrubbedBytes), 0);
    expect(_countParseableApp1(result.scrubbedBytes), 0);
  });

  test(
      'double-fault: corrupt length, then stray 0xFF00, then APP1 — '
      'resync chains until the APP1 marker', () async {
    final app1 = _exifApp1Segment();
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      0xFF, 0xE2, 0xFF, 0xFF, // APP2 with overrun length → resync…
      0xFF, 0x00, // …lands on a stuffed pair → resync again…
      ...app1, // …lands on the APP1 → stripped
      ..._sosAndScan,
    ]);
    final result = await svc.scrubMetadata(jpeg);
    expect(_countExifSignatures(result.scrubbedBytes), 0);
  });

  test(
      'a forged EOI inside a corrupt region truncates the stream — '
      'nothing after it ships', () async {
    final app1 = _exifApp1Segment();
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      0x77, 0x66, // non-marker garbage → resync
      0xFF, 0xD9, // fake EOI - resync lands here, stream ends
      ...app1, // post-EOI smuggle attempt
      ..._sosAndScan,
    ]);
    // NOTE: today this scrub produces a degenerate SOI+APP0+EOI output
    // that crashes the UNGUARDED readExifFromBytes verification pass at
    // :252 (see round7_scrub_unhandled_exceptions_test.dart). The
    // expectation below covers both halves of the fix: no throw, and
    // no Exif signature in what ships.
    late final ScrubbingResult result;
    try {
      result = await svc.scrubMetadata(jpeg);
    } catch (_) {
      fail('scrubMetadata threw instead of returning the truncated '
          'stream');
    }
    expect(_countExifSignatures(result.scrubbedBytes), 0);
  });

  test(
      'APP1 bytes embedded inside a copied DQT payload are not '
      'parseable as a segment (honesty bound — payload carriage only)',
      () async {
    final app1 = _exifApp1Segment();
    // DQT (non-stripped) whose declared length legally covers a whole
    // APP1 byte sequence as opaque payload.
    final dqtLen = app1.length + 2;
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      ..._jfifApp0,
      0xFF, 0xDB, (dqtLen >> 8) & 0xFF, dqtLen & 0xFF,
      ...app1, // inside DQT payload - copied verbatim by design
      ..._sosAndScan,
    ]);
    final result = await svc.scrubMetadata(jpeg);
    // The bytes ride through inside a legit segment - this is the
    // documented payload-carriage bound. What must hold: no PARSEABLE
    // APP1 exists at a segment boundary, and the verification pass
    // therefore cannot see the fields either (honest reporting).
    expect(_countParseableApp1(result.scrubbedBytes), 0,
        reason: 'payload-embedded APP1 must never sit at a real '
            'segment boundary in the output');
  });
}
