// RED TEAM PoC - Round-10: the round-9 allowlist narrowed the JPEG
// keep-set to decode-relevant markers and canonical APP0/APP14, but
// every kept segment is still emitted as
// `sublist(segStart, i + 2 + segLen)` - its declared-length payload is
// copied verbatim and never inspected
// (lib/services/metadata_scrubbing_service.dart:613-614). The
// assumption behind keeping opaque decode payloads is that no EXIF
// reader can surface what lives inside them. That assumption is
// false: package:exif's JPEG walker (_jpegReadParams,
// exif-3.3.0/lib/src/read_exif.dart:271-333) is NOT entropy-aware.
// Its dispatch recognises only FF E1/E0/E2/EE/DB/D8/EC - every other
// position (including SOS, 0xDA) falls to the `else` branch, which
// hops forward by an attacker-controlled 16-bit word
// (_incrementBase = data[base+2]*256 + data[base+3] + 2). After an
// SOS the walk therefore marches THROUGH the entropy-coded data using
// fake "lengths" the attacker plants there - it can be aimed at an
// arbitrary absolute offset, including the middle of a subsequent
// kept segment's payload.
//
// Attack construction (all offsets relative to the SCRUBBED stream,
// which is what the verification pass reads):
//
//   SOI  FF D8
//   APP0 canonical JFIF (kept, re-emitted byte-identical)
//   SOS  FF DA 00 08 … - kept; the reader's else-branch hops its real
//        declared length and lands on the first entropy byte
//   "entropy"  11 22 00 0C - emitted verbatim by the scrubber (no
//        0xFF byte → the entropy walk copies it whole). The reader
//        sees [11 22] (no marker match) then hops by 0x000C + 2 = 14
//        bytes, landing exactly on the planted `FF E1` inside…
//   DQT  FF DB 00 43 - kept VERBATIM (decode-relevant). Its 65-byte
//        payload is a spec byte + 64 arbitrary quant-table values, in
//        which we embed `FF E1 <len> 'Exif\0\0' <TIFF>` at offset 6.
//   EOI  FF D9
//
// The reader lands on the plant, finds 'Exif' at +4, and parses a
// complete TIFF (Image Make = 'RED') out of the DQT payload. The
// segment is a fully legal DQT - one 8-bit quant table; table values
// are unconstrained - so the output remains a decodable JPEG.
//
// Consequence: after scrubbing, `extractMetadata`/`detectSensitiveFields`
// on the OUTPUT still return sensitive fields. removedFields stays
// technically honest (it only claims what verifiably disappeared),
// but the privacy guarantee the scrub exists to provide - "the
// shipped bytes no longer yield the stripped metadata to a standard
// read" - is violated: the field survives in a form the app's own
// extractor returns. This is distinct from pixel steganography: no
// LSB/decode work is needed, `readExifFromBytes` hands the value back
// on the normal API path. And because the plant rides inside a
// kept-payload, the round-9 survival criterion - no `FF E1 'Exif'`
// pattern anywhere in the output - is still broken.
import 'dart:typed_data';
import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';
import '../fixtures/exif_fixture_generator.dart';

const _jfifApp0 = <int>[
  0xFF, 0xE0, 0x00, 0x10, // APP0, length 16
  0x4A, 0x46, 0x49, 0x46, 0x00, // 'JFIF\0'
  0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
];

/// Canonical SOS header (1 component, full spectral range) - kept
/// verbatim by the allowlist; the exif reader hops its declared
/// length (0x0008) and lands on the byte right after it.
const _sos = <int>[
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
];

/// A kept-marker segment (DQT, 0xDB) whose payload embeds a complete
/// `FF E1 … 'Exif\0\0' TIFF` block at [plantOffset]. The payload is a
/// structurally valid DQT: spec byte 0x00 (8-bit table 0) followed by
/// arbitrary table values. The TIFF inside yields 'Image Make'='RED'.
List<int> _dqtWithPlantedExif() {
  final payload = List<int>.filled(65, 0x01); // legal quant values
  payload[0] = 0x00; // DQT spec byte: Pq=0 (8-bit), Tq=0
  const p = 6; // plant offset inside the payload
  // Planted APP1 header - the exif reader is steered onto this `FF E1`.
  payload[p + 0] = 0xFF;
  payload[p + 1] = 0xE1;
  payload[p + 2] = 0x01; // fake APP1 length (ignored by the reader)
  payload[p + 3] = 0x01;
  payload[p + 4] = 0x45; // 'E'
  payload[p + 5] = 0x78; // 'x'
  payload[p + 6] = 0x69; // 'i'
  payload[p + 7] = 0x66; // 'f'
  payload[p + 8] = 0x00;
  payload[p + 9] = 0x00;
  // TIFF header at p+10 - big-endian, magic 42, IFD0 at +8.
  payload[p + 10] = 0x4D; // 'M'
  payload[p + 11] = 0x4D; // 'M'
  payload[p + 12] = 0x00;
  payload[p + 13] = 0x2A;
  payload[p + 14] = 0x00;
  payload[p + 15] = 0x00;
  payload[p + 16] = 0x00;
  payload[p + 17] = 0x08; // IFD0 offset = 8 → p+18
  // IFD0 at p+18: one entry.
  payload[p + 18] = 0x00;
  payload[p + 19] = 0x01;
  // Entry: tag 0x010F (Make), type 2 (ASCII), count 4, inline 'RED\0'.
  payload[p + 20] = 0x01;
  payload[p + 21] = 0x0F;
  payload[p + 22] = 0x00;
  payload[p + 23] = 0x02;
  payload[p + 24] = 0x00;
  payload[p + 25] = 0x00;
  payload[p + 26] = 0x00;
  payload[p + 27] = 0x04;
  payload[p + 28] = 0x52; // 'R'
  payload[p + 29] = 0x45; // 'E'
  payload[p + 30] = 0x44; // 'D'
  payload[p + 31] = 0x00;
  payload[p + 32] = 0x00; // next IFD = 0
  payload[p + 33] = 0x00;
  payload[p + 34] = 0x00;
  payload[p + 35] = 0x00;
  final segLen = payload.length + 2;
  return [
    0xFF,
    0xDB,
    (segLen >> 8) & 0xFF,
    segLen & 0xFF,
    ...payload,
  ];
}

/// "Entropy" bytes that steer the reader's fake-length hop onto the
/// plant. Scrubbed layout: SOI(2) APP0(18) SOS(10) → entropy starts
/// at absolute 30; the reader lands there after hopping the SOS, sees
/// no marker at [11 22], then hops (hi<<8|lo)+2. The DQT payload
/// starts at absolute 38, the planted FF E1 at 38+6=44, so the needed
/// hop is 44-30=14 → word = 12.
const _steeringEntropy = <int>[0x11, 0x22, 0x00, 0x0C];

/// Counts `FF E1 ?? ?? 'Exif'` patterns - the round-9 survival rule.
int _countExifMarkers(Uint8List bytes) {
  var count = 0;
  for (var i = 0; i + 7 < bytes.length; i++) {
    if (bytes[i] == 0xFF &&
        bytes[i + 1] == 0xE1 &&
        bytes[i + 4] == 0x45 &&
        bytes[i + 5] == 0x78 &&
        bytes[i + 6] == 0x69 &&
        bytes[i + 7] == 0x66) {
      count++;
    }
  }
  return count;
}

/// Complete `FF E1 <len> Exif…` APP1 segment out of the fixture JPEG.
Uint8List _exifApp1Segment() {
  final jpeg = buildSampleExifJpeg();
  final segLen = (jpeg[4] << 8) | jpeg[5];
  return Uint8List.fromList(jpeg.sublist(2, 2 + 2 + segLen));
}

void main() {
  final svc = MetadataScrubbingService(CidService());

  test(
      'a TIFF planted inside a kept DQT payload survives verbatim AND '
      'is surfaced by the app\'s own exif reader — the reader\'s '
      'segment walk is not entropy-aware and can be steered into kept '
      'payloads via fake lengths in the scan data', () async {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8, // SOI
      ..._jfifApp0,
      ..._exifApp1Segment(), // real APP1 (Make=Sony, GPS) - stripped
      ..._sos,
      ..._steeringEntropy,
      ..._dqtWithPlantedExif(), // kept verbatim - plant rides inside
      0xFF, 0xD9, // EOI
    ]);

    // Sanity: detection sees the real APP1 fields.
    expect(await svc.detectSensitiveFields(jpeg), isNotEmpty);

    final result =
        await svc.scrubMetadata(jpeg, options: ScrubbingOptions.full);

    expect(_countExifMarkers(result.scrubbedBytes), 0,
        reason: 'the round-9 criterion: no FF E1 `Exif` pattern may '
            'survive anywhere in the output — yet one rides inside the '
            'kept DQT payload, emitted verbatim.');

    // The stronger claim: the plant is not a dead byte channel - the
    // app's own extractor still returns the field from the scrubbed
    // bytes, because the exif reader hops through entropy data on
    // attacker-chosen lengths and lands on the planted FF E1.
    final meta = await svc.extractMetadata(result.scrubbedBytes);
    expect(meta?.cameraMake, isNull,
        reason: 'extractMetadata(scrubbed) still yields '
            "'Image Make'='RED' — the reader's non-entropy-aware "
            'forward scan (_incrementBase hops over SOS into '
            'attacker-controlled scan bytes) is aimed into the kept '
            'DQT payload. Sensitive metadata remains API-readable '
            'after scrubbing.');
    expect(meta?.exif.containsKey('Image Make') ?? false, isFalse);
  });

  test(
      'covert-only carrier: a JPEG whose ONLY metadata lives inside a '
      'kept payload scrubs to byte-identical output (wasModified '
      'false) yet still yields the field to extractMetadata', () async {
    // No real APP1 at all - the only metadata is the DQT-payload
    // plant. Detection DOES see it (same steered walk applies to the
    // input), but nothing is stripped: every segment is decode-
    // relevant, so the output is byte-identical and the caller ships
    // the original believing it clean.
    final jpeg = Uint8List.fromList([
      0xFF,
      0xD8,
      ..._jfifApp0,
      ..._sos,
      ..._steeringEntropy,
      ..._dqtWithPlantedExif(),
      0xFF,
      0xD9,
    ]);

    final result =
        await svc.scrubMetadata(jpeg, options: ScrubbingOptions.full);

    final leaked = await readExifFromBytes(result.scrubbedBytes);
    expect(leaked.containsKey('Image Make'), isFalse,
        reason: 'the planted TIFF inside the kept DQT payload is '
            'parsed by readExifFromBytes on the scrubbed output — '
            "'Image Make' remains surfaceable though no metadata "
            'segment exists at the top level.');
    expect(result.wasModified || leaked.isEmpty, isTrue,
        reason: 'output is byte-identical to the input yet still '
            'carries reader-visible metadata — the adoption gate '
            '(wasModified) reports "nothing to change" while the '
            'file leaks through the kept-payload channel.');
  });
}
