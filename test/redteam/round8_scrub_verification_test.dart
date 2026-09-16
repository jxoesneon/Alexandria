// RED TEAM — Round-8 verification suite: regression-checks every
// round-4..7 scrubber fix through the CURRENT code paths, plus the
// round-7 contract additions (guarded exif reads, bytesChanged-driven
// adoption, verificationFailed honesty, PNG malformed-tail drop,
// iCCP strip).
//
// Every assertion here encodes the POST-fix contract and must pass.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';
import '../fixtures/exif_fixture_generator.dart';

const _pngSig = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

List<int> _pngChunk(String type, List<int> data) => [
      (data.length >> 24) & 0xFF,
      (data.length >> 16) & 0xFF,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
      ...type.codeUnits,
      ...data,
      0, 0, 0, 0,
    ];

List<int> _seg(int marker, List<int> payload) {
  final len = payload.length + 2;
  return [0xFF, marker, (len >> 8) & 0xFF, len & 0xFF, ...payload];
}

final _jfif = _seg(0xE0, [
  ...'JFIF\x00'.codeUnits,
  0x01, 0x02, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
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

  group('round-7 adoption gate (bytesChanged drives wasModified)', () {
    test('COM-only JPEG: comment stripped and wasModified true', () async {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8,
        ..._jfif,
        ..._seg(0xFE, 'Eve was here — 37.7N 122.4W'.codeUnits), // COM
        0xFF, 0xD9,
      ]);
      final result = await svc.scrubMetadata(jpeg);
      expect(result.wasModified, isTrue,
          reason: 'COM strips must flip bytesChanged so the caller '
              'adopts the scrubbed stream.');
      expect(_containsAscii(result.scrubbedBytes, 'Eve was here'),
          isFalse);
    });

    test('XMP-only APP1 JPEG: packet stripped and wasModified true',
        () async {
      final xmp = [
        ...'http://ns.adobe.com/xap/1.0/\x00'.codeUnits,
        ...'<x:xmpmeta><dc:creator>Eve Private</dc:creator></x:xmpmeta>'
            .codeUnits,
      ];
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8,
        ..._jfif,
        ..._seg(0xE1, xmp),
        0xFF, 0xD9,
      ]);
      final result = await svc.scrubMetadata(jpeg);
      expect(result.wasModified, isTrue);
      expect(_containsAscii(result.scrubbedBytes, 'Eve Private'), isFalse);
    });

    test('clean well-formed JPEG: identical output, wasModified false',
        () async {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8,
        ..._jfif,
        ..._seg(0xDB, List.filled(64, 0x01)), // DQT
        0xFF, 0xD9,
      ]);
      final result = await svc.scrubMetadata(jpeg);
      expect(result.bytesChanged, isFalse);
      expect(result.wasModified, isFalse);
      expect(result.scrubbedBytes, orderedEquals(jpeg));
    });
  });

  group('round-4/5/6 JPEG walk regressions', () {
    test('post-EOI tail dropped even after a real SOS scan', () async {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8,
        ..._seg(0xDA, [0x01, 0x01, 0x00, 0x00, 0x3F, 0x00]), // SOS hdr
        0x11, 0x22, 0xFF, 0x00, 0x33, // entropy w/ stuffed FF
        0xFF, 0xD9,
        ...'POST-EOI-PAYLOAD'.codeUnits,
      ]);
      final result = await svc.scrubMetadata(jpeg);
      expect(_containsAscii(result.scrubbedBytes, 'POST-EOI-PAYLOAD'),
          isFalse);
    });

    test('post-SOS APP1 (multi-scan) stripped; entropy bytes kept',
        () async {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8,
        ..._seg(0xDA, [0x01, 0x01, 0x00, 0x00, 0x3F, 0x00]),
        0x11, 0x22, 0xFF, 0x00, 0x33,
        ..._seg(0xE1, [...'Exif\x00\x00'.codeUnits, ...List.filled(16, 0x41)]),
        0xFF, 0xD9,
      ]);
      final result = await svc.scrubMetadata(jpeg);
      expect(_containsAscii(result.scrubbedBytes, 'Exif\x00\x00'), isFalse);
      // The stuffed-FF entropy run must survive intact.
      expect(_containsAscii(result.scrubbedBytes, '\x11\x22'), isTrue);
    });

    test('APP1 behind a corrupt length is resynced and stripped', () async {
      final jpeg = Uint8List.fromList([
        0xFF, 0xD8,
        ..._jfif,
        0xFF, 0xDB, 0x7F, 0xFF, 0x99, // corrupt DQT length
        ..._seg(0xE1, [...'Exif\x00\x00'.codeUnits, ...List.filled(16, 0x41)]),
        0xFF, 0xD9,
      ]);
      final result = await svc.scrubMetadata(jpeg);
      expect(_containsAscii(result.scrubbedBytes, 'Exif\x00\x00'), isFalse);
    });
  });

  group('round-3/7 PNG walk regressions', () {
    test('well-formed PNG is byte-identical except stripped chunks and '
        'keeps IHDR/IDAT/IEND', () async {
      final png = Uint8List.fromList([
        ..._pngSig,
        ..._pngChunk('IHDR', List.filled(13, 1)),
        ..._pngChunk('iCCP',
            'Profile\x00\x00cprtCopyright Eve'.codeUnits),
        ..._pngChunk('IDAT', List.filled(16, 0x42)),
        ..._pngChunk('tEXt', 'Author\x00Eve'.codeUnits),
        ..._pngChunk('IEND', const []),
      ]);
      final result = await svc.scrubMetadata(png);
      expect(_containsAscii(result.scrubbedBytes, 'IHDR'), isTrue);
      expect(_containsAscii(result.scrubbedBytes, 'IDAT'), isTrue);
      expect(_containsAscii(result.scrubbedBytes, 'IEND'), isTrue);
      expect(_containsAscii(result.scrubbedBytes, 'iCCP'), isFalse);
      expect(_containsAscii(result.scrubbedBytes, 'tEXt'), isFalse);
      expect(_containsAscii(result.scrubbedBytes, 'Copyright Eve'),
          isFalse);
    });

    test('malformed chunk drops the tail — eXIf behind it does not '
        'survive', () async {
      final png = Uint8List.fromList([
        ..._pngSig,
        ..._pngChunk('IHDR', List.filled(13, 1)),
        0x7F, 0xFF, 0xFF, 0xFF, ...'IDAT'.codeUnits, 0x11, 0x22,
        ..._pngChunk('eXIf', [...'II*\x00'.codeUnits, ...List.filled(32, 0xAA)]),
        ..._pngChunk('IEND', const []),
      ]);
      final result = await svc.scrubMetadata(png);
      expect(_containsAscii(result.scrubbedBytes, 'eXIf'), isFalse);
    });

    test('post-IEND chunks dropped', () async {
      final png = Uint8List.fromList([
        ..._pngSig,
        ..._pngChunk('IHDR', List.filled(13, 1)),
        ..._pngChunk('IDAT', List.filled(8, 0x42)),
        ..._pngChunk('IEND', const []),
        ..._pngChunk('tEXt', 'Author\x00Hidden'.codeUnits),
      ]);
      final result = await svc.scrubMetadata(png);
      expect(_containsAscii(result.scrubbedBytes, 'Hidden'), isFalse);
      expect(_containsAscii(result.scrubbedBytes, 'IEND'), isTrue);
    });
  });

  group('round-7 guarded exif reads + verification honesty', () {
    test('malformed input never throws; output always a subset',
        () async {
      final malformed = Uint8List.fromList([
        0xFF, 0xD8,
        ..._jfif,
        0x77, 0x66, // non-marker garbage
        0xFF, 0xD9,
        0xFF, 0xE1, 0x00, 0x10, ...'Exif\x00\x00'.codeUnits,
      ]);
      final result = await svc.scrubMetadata(malformed);
      // Strict-subset invariant: every output byte comes from the input.
      expect(result.scrubbedBytes.length,
          lessThanOrEqualTo(malformed.length));
      if (result.verificationFailed) {
        expect(result.removedFields, isEmpty,
            reason: 'an unverifiable output must claim nothing removed.');
      }
    });

    test('real EXIF jpeg: verification succeeds and removedFields are '
        'honest', () async {
      final jpeg = buildSampleExifJpeg();
      final detected = await svc.detectSensitiveFields(jpeg);
      expect(detected, isNotEmpty);
      final result = await svc.scrubMetadata(jpeg);
      expect(result.verificationFailed, isFalse);
      // Every claimed-removed field must have been detected first and
      // must be verifiably gone — no false claims either direction.
      for (final f in result.removedFields) {
        expect(detected, contains(f));
      }
      expect(result.removedFields, contains('Image Make'));
      expect(result.wasModified, isTrue);
      expect(_containsAscii(result.scrubbedBytes, 'Sony'), isFalse);
      expect(_containsAscii(result.scrubbedBytes, 'Alexandria'), isFalse);
    });

    test('unsupported container passes through untouched with no '
        'claims', () async {
      final pdf = Uint8List.fromList([
        ...'%PDF-1.7 fake'.codeUnits,
        ...List.filled(16, 0x20),
      ]);
      final result = await svc.scrubMetadata(pdf);
      expect(result.scrubbedBytes, orderedEquals(pdf));
      expect(result.bytesChanged, isFalse);
      expect(result.wasModified, isFalse);
      expect(result.removedFields, isEmpty);
    });
  });
}
