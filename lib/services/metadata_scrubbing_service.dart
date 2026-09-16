import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:exif/exif.dart';
import 'cid_service.dart';

/// Provider for the MetadataScrubbingService
final metadataScrubbingServiceProvider = Provider((ref) {
  final cidService = ref.watch(cidServiceProvider);
  return MetadataScrubbingService(cidService);
});

/// EXIF fields to remove for anonymity (Spec §11.4)
class ScrubbableFields {
  static const List<String> gpsFields = [
    'GPS GPSLatitude',
    'GPS GPSLatitudeRef',
    'GPS GPSLongitude',
    'GPS GPSLongitudeRef',
    'GPS GPSAltitude',
    'GPS GPSAltitudeRef',
    'GPS GPSTimeStamp',
    'GPS GPSDateStamp',
  ];

  static const List<String> deviceFields = [
    'Image Make',
    'Image Model',
    'EXIF BodySerialNumber',
    'EXIF LensSerialNumber',
    'Image Software',
    'EXIF MakerNote',
  ];

  static const List<String> authorFields = [
    'Image Artist',
    'Image Copyright',
    'EXIF UserComment',
    'Image ImageDescription',
    'XMP Creator',
    'XMP Rights',
  ];

  static const List<String> timestampFields = [
    'EXIF DateTimeOriginal',
    'EXIF DateTimeDigitized',
    'Image DateTime',
    'EXIF SubSecTimeOriginal',
    'EXIF SubSecTimeDigitized',
    'EXIF SubSecTime',
  ];

  static List<String> get allFields => [
        ...gpsFields,
        ...deviceFields,
        ...authorFields,
        ...timestampFields,
      ];
}

/// Options for metadata scrubbing
class ScrubbingOptions {
  final bool removeGps;
  final bool removeDevice;
  final bool removeAuthor;
  final bool removeTimestamps;

  const ScrubbingOptions({
    this.removeGps = true,
    this.removeDevice = true,
    this.removeAuthor = true,
    this.removeTimestamps = false, // Often useful to keep
  });

  static const ScrubbingOptions full = ScrubbingOptions(
    removeGps: true,
    removeDevice: true,
    removeAuthor: true,
    removeTimestamps: true,
  );

  static const ScrubbingOptions privacy = ScrubbingOptions(
    removeGps: true,
    removeDevice: true,
    removeAuthor: true,
    removeTimestamps: false,
  );

  List<String> get fieldsToRemove {
    final fields = <String>[];
    if (removeGps) fields.addAll(ScrubbableFields.gpsFields);
    if (removeDevice) fields.addAll(ScrubbableFields.deviceFields);
    if (removeAuthor) fields.addAll(ScrubbableFields.authorFields);
    if (removeTimestamps) fields.addAll(ScrubbableFields.timestampFields);
    return fields;
  }
}

/// Result of metadata scrubbing
class ScrubbingResult {
  final Uint8List scrubbedBytes;
  final String newCid;
  final List<String> removedFields;
  final int originalSize;
  final int scrubbedSize;

  /// True when the scrubber actually rewrote the byte stream -
  /// [scrubbedBytes] differs from the input. This is the correct
  /// adoption signal: the JPEG/PNG walkers strip COM, every
  /// non-decode-relevant APPn (Exif/XMP APP1, ICC APP2, IPTC APP13,
  /// Ducky APP12, … - round-8 red finding), non-canonical APP0/APP14
  /// and every reserved/unassigned marker (round-9 red finding -
  /// the JPEG dispatch is a decode-relevant allowlist), and textual
  /// PNG chunks whether or not the exif reader can parse them, so
  /// detector
  /// coverage must never gate whether the
  /// cleaned output is used (round-7 red finding: keying adoption on
  /// removedFields alone silently shipped the ORIGINAL bytes for
  /// COM-only and XMP-only files).
  final bool bytesChanged;

  /// True when the post-scrub verification pass could not run - the
  /// exif reader threw on the scrubbed output. In that case
  /// [removedFields] is empty BY CONSTRUCTION (nothing unverifiable is
  /// claimed), but [scrubbedBytes] is still adoptable: the strippers
  /// only ever drop bytes, so the output is a strict subset of the
  /// input with every known metadata carrier removed (round-7 red
  /// finding - the unguarded verification read used to crash the
  /// whole upload).
  final bool verificationFailed;

  ScrubbingResult({
    required this.scrubbedBytes,
    required this.newCid,
    required this.removedFields,
    required this.originalSize,
    required this.scrubbedSize,
    this.bytesChanged = false,
    this.verificationFailed = false,
  });

  /// Whether the caller should ship [scrubbedBytes] instead of the
  /// original. Keyed on [bytesChanged] (the scrubber rewrote the
  /// stream) - NOT solely on removedFields, which only reflects what
  /// the exif detector could see (round-7 red finding).
  bool get wasModified => bytesChanged || removedFields.isNotEmpty;
  int get sizeReduction => originalSize - scrubbedSize;
}

/// Extracted metadata before scrubbing
class ExtractedMetadata {
  final Map<String, dynamic> exif;
  final String? gpsLocation;
  final String? cameraMake;
  final String? cameraModel;
  final String? author;
  final DateTime? dateTime;

  ExtractedMetadata({
    required this.exif,
    this.gpsLocation,
    this.cameraMake,
    this.cameraModel,
    this.author,
    this.dateTime,
  });

  factory ExtractedMetadata.fromExifData(Map<String, IfdTag?> data) {
    String? gps;
    if (data.containsKey('GPS GPSLatitude') &&
        data.containsKey('GPS GPSLongitude')) {
      gps = '${data['GPS GPSLatitude']}, ${data['GPS GPSLongitude']}';
    }

    return ExtractedMetadata(
      exif: data.map((k, v) => MapEntry(k, v?.printable ?? '')),
      gpsLocation: gps,
      cameraMake: data['Image Make']?.printable,
      cameraModel: data['Image Model']?.printable,
      author: data['Image Artist']?.printable,
      dateTime: _parseDateTime(data['EXIF DateTimeOriginal']?.printable),
    );
  }

  static DateTime? _parseDateTime(String? str) {
    if (str == null) return null;
    try {
      // EXIF format: "YYYY:MM:DD HH:MM:SS"
      final parts = str.split(' ');
      if (parts.length != 2) return null;
      final dateParts = parts[0].split(':');
      final timeParts = parts[1].split(':');
      if (dateParts.length != 3 || timeParts.length != 3) return null;
      return DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      );
    } catch (e) {
      return null;
    }
  }

  bool get hasLocation => gpsLocation != null;
  bool get hasDeviceInfo => cameraMake != null || cameraModel != null;
  bool get hasAuthor => author != null;
}

/// Service for removing sensitive metadata from files
class MetadataScrubbingService {
  final CidService _cidService;

  /// Hard input ceiling for [scrubMetadata] (campaign-2 hardening -
  /// service-side bound, not just UI-side). AddContentScreen already
  /// refuses files above 512 MiB before any byte buffer is touched,
  /// but every other caller of this service (headless SDK, plugins,
  /// future screens) reached the scrubber unbounded. The bound is
  /// deliberately the same 512 MiB:
  ///   * the PNG chunk walk trusts a 32-bit declared length per chunk
  ///     (`end = i + 12 + len`); inputs above ~4 GiB make that
  ///     arithmetic the steering surface the UI cap was added for;
  ///   * the exif reader parses the full buffer and the scrubbers
  ///     build a second output buffer - an unbounded input is a
  ///     memory-exhaustion primitive;
  ///   * 512 MiB stays far under the 2 GiB mark where the declared
  ///     chunk lengths can start steering reads.
  /// Inputs over the ceiling are REFUSED explicitly (ArgumentError)
  /// rather than scrubbed partially or silently - a caller must never
  /// ship a file believing it was cleaned when the scrubber declined
  /// to process it.
  static const int defaultMaxInputBytes = 512 * 1024 * 1024;

  /// Active ceiling - injectable so tests can exercise the refusal
  /// without allocating half a gigabyte.
  final int maxInputBytes;

  MetadataScrubbingService(
    this._cidService, {
    this.maxInputBytes = defaultMaxInputBytes,
  });

  /// Extract metadata from image bytes
  Future<ExtractedMetadata?> extractMetadata(Uint8List bytes) async {
    try {
      final data = await readExifFromBytes(bytes);
      if (data.isEmpty) return null;
      return ExtractedMetadata.fromExifData(data);
    } catch (e) {
      return null;
    }
  }

  /// Check if file contains sensitive metadata
  Future<List<String>> detectSensitiveFields(Uint8List bytes) async {
    try {
      final data = await readExifFromBytes(bytes);
      final sensitive = <String>[];

      for (final field in ScrubbableFields.allFields) {
        if (data.containsKey(field)) {
          sensitive.add(field);
        }
      }

      return sensitive;
    } catch (e) {
      return [];
    }
  }

  /// Scrub metadata from image bytes.
  ///
  /// REAL removal (round-2 red finding - the previous implementation
  /// returned the input bytes verbatim while reporting fields as
  /// removed). For JPEG we walk the marker stream through a
  /// decode-relevant ALLOWLIST (round-9 red finding): only the
  /// frame/entropy structure, the canonical 'JFIF\0' APP0 and the
  /// canonical 'Adobe' APP14 survive - all other APPn (APP1/Exif+XMP,
  /// APP2/ICC, APP12/Ducky, APP13/IPTC, JFXX/extension APP0,
  /// non-Adobe APP14, …), COM and every reserved/unassigned marker
  /// are dropped; for PNG
  /// we drop textual/eXIf/tIME ancillary chunks. removedFields then
  /// reports only fields VERIFIABLY absent from the returned bytes -
  /// fields detected but not actually stripped are never claimed.
  Future<ScrubbingResult> scrubMetadata(
    Uint8List bytes, {
    ScrubbingOptions options = ScrubbingOptions.privacy,
  }) async {
    // (campaign-2 hardening) refuse oversized input explicitly - see
    // [maxInputBytes] for why the ceiling exists and why it matches
    // the UI ingest cap. This throws BEFORE any parse or buffer copy
    // so an over-ceiling buffer is never half-processed.
    if (bytes.length > maxInputBytes) {
      throw ArgumentError.value(
        bytes.length,
        'bytes',
        'input exceeds the ${maxInputBytes ~/ (1024 * 1024)} MiB '
            'scrubber ceiling — refusing to process rather than '
            'mis-scrubbing a truncated view',
      );
    }
    // Detect what fields exist. (round-7 red finding) the exif reader
    // is invoked GUARDED now - exif-3.3.0 throws RangeError on
    // truncated PNG chunk headers, overrun chunk lengths, and
    // degenerate JPEG streams, and the previous unguarded call aborted
    // the entire upload for any corrupt-but-sniffable image. A parse
    // failure degrades to an empty detection set; the byte-level
    // strippers below do not depend on the exif parse and still run.
    Map<String, IfdTag> data;
    try {
      data = await readExifFromBytes(bytes);
    } catch (_) {
      data = const {};
    }
    final fieldsToRemove = options.fieldsToRemove.toSet();
    final wanted = <String>{
      for (final f in data.keys)
        if (fieldsToRemove.contains(f)) f,
    };

    final mime = detectFileType(bytes);
    Uint8List scrubbedBytes;
    switch (mime) {
      case 'image/jpeg':
        scrubbedBytes = _stripJpegMetadataSegments(bytes);
      case 'image/png':
        scrubbedBytes = _stripPngMetadataChunks(bytes);
      default:
        // Unknown/unsupported container: we cannot verifiably strip -
        // return the input unchanged and report nothing as removed
        // rather than claiming a scrub that did not happen.
        scrubbedBytes = bytes;
    }

    // Verify claims: re-detect on the OUTPUT and only report fields that
    // are genuinely gone from the scrubbed bytes. (round-7 red finding)
    // This read is guarded too - the scrubber's own output can itself be
    // degenerate (e.g. a JPEG resynced down to SOI+APP0+EOI crashes the
    // reader inside _jpegReadParams), and the previous unguarded call
    // crashed the upload on exactly the malformed inputs the round-6
    // resync was built to survive. When verification cannot run we
    // report NOTHING as removed - an unverifiable output is never
    // claimed clean - but the scrubbed stream is still returned because
    // the strippers only ever drop bytes.
    Map<String, IfdTag>? remaining;
    var verificationFailed = false;
    try {
      remaining = await readExifFromBytes(scrubbedBytes);
    } catch (_) {
      verificationFailed = true;
    }
    final removedFields = verificationFailed
        ? <String>[]
        : wanted.where((f) => !remaining!.containsKey(f)).toList();

    final newCid = _cidService.cidFromBytes(scrubbedBytes);

    return ScrubbingResult(
      scrubbedBytes: scrubbedBytes,
      newCid: newCid,
      removedFields: removedFields,
      originalSize: bytes.length,
      scrubbedSize: scrubbedBytes.length,
      bytesChanged: !_bytesEqual(scrubbedBytes, bytes),
      verificationFailed: verificationFailed,
    );
  }

  /// Byte-for-byte comparison used to detect whether the scrubber
  /// actually rewrote the stream - independent of what the exif
  /// detector could see (round-7 red finding).
  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// JPEG segment markers whose payload a decoder actually needs -
  /// the keep-ALLOWLIST for the marker walk below.
  ///
  /// (round-9 red finding) The previous dispatch was a denylist
  /// (_jpegStrippedMarkers: all of 0xE1-0xEF except 0xE0/0xEE, plus
  /// COM - the round-8 fix) that inspected ONLY the marker byte and
  /// then copied the declared-length payload VERBATIM. Every kept
  /// marker was therefore an uninspected byte channel:
  ///   * JFXX APP0 (0xE0) - JFIF extension 0x10 embeds a COMPLETE
  ///     inner JPEG stream that can carry its own Exif/GPS APP1,
  ///     invisible to the exif reader's segment walker;
  ///   * APP14 (0xEE) - kept without checking the 'Adobe' signature
  ///     or bounding it to the canonical 14-byte segment, so an
  ///     oversized/bogus payload shipped arbitrary bytes;
  ///   * reserved/unassigned markers - JPGn 0xF0-0xFD, JPG 0xC8 and
  ///     the unassigned 0x02-0xBF range - were never in the strip
  ///     set, so their payloads emitted verbatim, including markers
  ///     fabricated behind a corrupt segment that the round-6 resync
  ///     (_nextJpegMarker) lands on.
  /// The allowlist below keeps only decode-relevant structure and
  /// drops every other marker's payload - fail closed.
  ///
  /// Membership, per ITU T.81 / libjpeg semantics:
  ///   * SOFn frame headers 0xC0-0xCF EXCEPT 0xC4 (DHT), 0xC8
  ///     (JPG-reserved - never a frame header, dropped) and 0xCC
  ///     (DAC, listed separately). SOF3 (0xC3, lossless sequential)
  ///     and the differential/arithmetic SOFn stay because they ARE
  ///     frame headers a capable decoder requires.
  ///   * 0xC4 DHT, 0xDB DQT, 0xDD DRI, 0xDA SOS, 0xDC DNL - required
  ///     entropy/frame structure (DNL redefines the line count when
  ///     a SOF defers it).
  ///   * 0xCC DAC - required by arithmetic-coded scans.
  ///   * 0xDE/0xDF DHP/EXP - hierarchical-mode structure.
  ///   * APP0 (0xE0) and APP14 (0xEE) are deliberately NOT in this
  ///     set - they are kept only when the PAYLOAD is canonical
  ///     ('JFIF\0' header / 'Adobe' 12-byte record); the dispatch
  ///     site enforces that.
  /// Everything else is dropped: all other APPn (Exif/XMP APP1,
  /// ICC APP2, 'Meta' APP3, Ducky APP12, IPTC APP13, JPEG-XT APP15),
  /// non-canonical/extended APP0 (JFXX and friends), non-'Adobe' or
  /// oversized APP14, COM (0xFE), JPG-reserved 0xC8, the JPGn block
  /// 0xF0-0xFD (T.81-reserved; JPEG-LS's SOF55/LSE live there too but
  /// this scrubber targets T.81 streams - dropping fails closed), and
  /// the unassigned 0x02-0xBF range.
  static const Set<int> _jpegKeptSegmentMarkers = {
    0xC0, 0xC1, 0xC2, 0xC3, // SOF0-3 (baseline/extended/progressive/lossless)
    0xC5, 0xC6, 0xC7, // SOF5-7 (differential Huffman)
    0xC9, 0xCA, 0xCB, // SOF9-11 (arithmetic)
    0xCD, 0xCE, 0xCF, // SOF13-15 (differential arithmetic)
    0xC4, // DHT - Huffman tables
    0xCC, // DAC - arithmetic conditioning
    0xDA, // SOS - scan header (entropy walk follows)
    0xDB, // DQT - quantization tables
    0xDC, // DNL - deferred line count
    0xDD, // DRI - restart interval
    0xDE, 0xDF, // DHP/EXP - hierarchical mode
  };

  /// True when the APP0 segment at marker index [i] (declared length
  /// [segLen], already bounds-checked) carries the canonical JFIF
  /// identifier 'JFIF\0' and is long enough to hold the fixed 14-byte
  /// JFIF header (round-9 red finding - the marker byte alone used to
  /// keep JFXX extension APP0s verbatim).
  static bool _isJfifApp0(Uint8List bytes, int i, int segLen) {
    return segLen >= 16 &&
        bytes[i + 4] == 0x4A && // 'J'
        bytes[i + 5] == 0x46 && // 'F'
        bytes[i + 6] == 0x49 && // 'I'
        bytes[i + 7] == 0x46 && // 'F'
        bytes[i + 8] == 0x00;
  }

  /// True when the APP14 segment at marker index [i] is the canonical
  /// 'Adobe' color-transform record - a 12-byte payload ('Adobe' +
  /// version(2) + flags0(2) + flags1(2) + transform(1)), i.e. a
  /// declared length of exactly 14 (round-9 red finding - an unbounded
  /// APP14 keep shipped arbitrary payload verbatim).
  static bool _isCanonicalAdobeApp14(Uint8List bytes, int i, int segLen) {
    return segLen == 14 &&
        bytes[i + 4] == 0x41 && // 'A'
        bytes[i + 5] == 0x64 && // 'd'
        bytes[i + 6] == 0x6F && // 'o'
        bytes[i + 7] == 0x62 && // 'b'
        bytes[i + 8] == 0x65; //   'e'
  }

  static final List<int> _sigExif = 'Exif'.codeUnits;
  static final List<int> _sigDucky = 'Ducky'.codeUnits;
  static final List<int> _sigAdobe = 'Adobe'.codeUnits;
  static final List<int> _sigTiffLE = 'II*\x00'.codeUnits;
  static final List<int> _sigTiffBE = 'MM\x00*'.codeUnits;

  /// (round-10 red finding) Metadata signatures that must never
  /// survive inside a KEPT JPEG segment's payload. Kept payloads
  /// (DQT/DHT/SOF/SOS/DRI/DNL/DAC/DHP/EXP) are unconstrained bytes the
  /// scrubber used to copy verbatim - a complete
  /// `FF E1 'Exif\0\0' <TIFF>` planted inside a structurally valid DQT
  /// rode straight through. package:exif's JPEG walker
  /// (_jpegReadParams, exif-3.3.0 read_exif.dart:271-333) is NOT
  /// entropy-aware: after SOS its else-branch hops forward by
  /// attacker-chosen 16-bit words, so planted scan bytes steer the
  /// reader onto an arbitrary absolute offset - including the middle
  /// of a kept segment's payload. Dropping any kept segment whose
  /// bytes carry a landing pad or a known metadata signature closes
  /// the channel at the source.
  ///
  /// 'Adobe' is deliberately NOT a bare needle - the canonical APP14
  /// payload legitimately starts with it; its only reader-terminal use
  /// (the `FF DB` landing pad) is covered by
  /// [_isJpegReaderLandingPad].
  static final List<List<int>> _jpegForbiddenPayloadSignatures = [
    'Exif'.codeUnits, // TIFF-in-APP1 header prefix ('Exif\0\0' incl.)
    'http://ns.adobe.com/'.codeUnits, // XMP APP1 + xmp/extension APP1
    '<x:xmpmeta'.codeUnits, // raw XMP packet (exiftool full-scan)
    'ICC_PROFILE'.codeUnits, // APP2 ICC profile signature
    'Photoshop'.codeUnits, // APP13 IRB carrier
    '8BIM'.codeUnits, // Photoshop image-resource block (IPTC)
    'XML:com.adobe.xmp'.codeUnits, // XMP alternate marker
    'Ducky'.codeUnits, // APP12 Ducky/PictureInfo block
  ];

  /// True when [sig] occurs in [bytes] at offset [at], bounded by
  /// [end] (exclusive).
  static bool _matchesAt(Uint8List bytes, int at, List<int> sig, int end) {
    if (at < 0 || at + sig.length > end) return false;
    for (var k = 0; k < sig.length; k++) {
      if (bytes[at + k] != sig[k]) return false;
    }
    return true;
  }

  /// (round-10 red finding) True when the 0xFF-prefixed code at [p] is
  /// a TERMINAL dispatch of the exif reader's JPEG walk - the byte
  /// pattern a steered read can land on to reach a metadata parse:
  ///   * `FF E1 ?? ?? 'Exif'` - the APP1 branch breaks the walk and a
  ///     TIFF is parsed from +12 (read_exif.dart:277-287, 335-341);
  ///   * `FF DB FF ?? ?? ?? <sig>` - the DQT branch breaks the walk,
  ///     and when the length-high byte is 0xFF the post-loop check
  ///     accepts 'Exif', 'Ducky' or 'Adobe' at +6 and parses a TIFF
  ///     from +12 (read_exif.dart:307-309, 336-355). A kept DQT (or a
  ///     fake `FF DB` inside another kept payload) can satisfy this.
  /// Every other recognised code (E0/E2/EE/EC/D8) only hops forward by
  /// the following 16-bit word - a steering primitive, never a
  /// terminal. [end] bounds the match window (segment end or stream
  /// end).
  static bool _isJpegReaderLandingPad(Uint8List bytes, int p, int end) {
    if (bytes[p] != 0xFF || p + 1 >= end) return false;
    final code = bytes[p + 1];
    if (code == 0xE1) {
      return _matchesAt(bytes, p + 4, _sigExif, end);
    }
    if (code == 0xDB && p + 2 < end && bytes[p + 2] == 0xFF) {
      return _matchesAt(bytes, p + 6, _sigExif, end) ||
          _matchesAt(bytes, p + 6, _sigDucky, end) ||
          _matchesAt(bytes, p + 6, _sigAdobe, end);
    }
    return false;
  }

  /// (round-10 red finding) True when the kept segment occupying
  /// [fillStart]..[segEnd] (marker code at [markerStart]+1, payload at
  /// [markerStart]+4; [fillStart] may lead with emitted 0xFF fill
  /// bytes that are themselves part of the pad surface) must NOT be
  /// emitted because its bytes carry reader-reachable or
  /// extractor-visible metadata:
  ///   * an exif-reader landing pad anywhere in the emitted region -
  ///     the steered walk lands on absolute offsets, so a fake
  ///     `FF E1`/`FF DB` anywhere in the payload is live;
  ///   * TIFF magic `II*\0`/`MM\x00*` at the payload start - an
  ///     embedded file where the segment's own format begins (no kept
  ///     marker's format legitimately starts with it: DQT/DHT spec
  ///     bytes, SOS component count and SOF precision all reject
  ///     'I'/'M');
  ///   * a known metadata signature ([_jpegForbiddenPayloadSignatures])
  ///     anywhere in the payload - dead weight for package:exif, but
  ///     surfaceable to exiftool-class scanners and a strong-smell
  ///     covert channel.
  static bool _jpegSegmentCarriesEmbeddedMetadata(
      Uint8List bytes, int fillStart, int markerStart, int segEnd) {
    for (var p = fillStart; p + 1 < segEnd; p++) {
      if (bytes[p] == 0xFF && _isJpegReaderLandingPad(bytes, p, segEnd)) {
        return true;
      }
    }
    final payloadStart = markerStart + 4;
    if (payloadStart >= segEnd) return false;
    if (_matchesAt(bytes, payloadStart, _sigTiffLE, segEnd) ||
        _matchesAt(bytes, payloadStart, _sigTiffBE, segEnd)) {
      return true;
    }
    for (final sig in _jpegForbiddenPayloadSignatures) {
      for (var p = payloadStart; p + sig.length <= segEnd; p++) {
        if (_matchesAt(bytes, p, sig, segEnd)) return true;
      }
    }
    return false;
  }

  /// Rewrites a JPEG stream keeping ONLY decode-relevant structure -
  /// the marker dispatch is an allowlist, not a denylist (round-9 red
  /// finding). Kept verbatim: standalone markers (TEM, RST0-7, SOI),
  /// EOI (which terminates the walk), and the length-bearing segments
  /// in [_jpegKeptSegmentMarkers] (SOFn, DHT, DQT, DRI, SOS, DNL, DAC,
  /// DHP/EXP). APP0 is kept only as a NORMALIZED canonical JFIF
  /// header - 'JFIF\0' signature required, fixed 16-byte form
  /// re-emitted with thumbnail dims zeroed, so JFXX extensions, raw
  /// JFIF thumbnails, and any declared-length trailer cannot ride
  /// through. APP14 is kept only as the canonical 14-byte 'Adobe'
  /// transform record. Everything else - all other APPn
  /// (Exif/XMP APP1, ICC APP2, IPTC APP13, Ducky APP12, …), COM,
  /// JPG-reserved 0xC8, JPGn 0xF0-0xFD, and unassigned markers - is
  /// dropped, so no kept segment is an uninspected metadata channel.
  ///
  /// The walk is deliberately fail-safe: on a malformed marker the
  /// walker resynchronises forward to the next plausible marker and
  /// DROPS the unparseable region - it is never copied verbatim, so no
  /// metadata-bearing segment can ride through behind corrupt bytes
  /// (round-6 red finding: the previous verbatim-tail bail-outs let a
  /// complete APP1/Exif+GPS segment survive past any corrupt length,
  /// stray 0xFF00, or non-marker byte, while removedFields still claimed
  /// the fields as removed). Segments essential to decoding - SOI, the
  /// canonical JFIF APP0 and Adobe APP14, DQT/DHT/SOF/SOS/DRI/DNL/DAC
  /// and the entropy-coded scan - are preserved.
  ///
  /// (round-5 red finding) SOS is NOT the end of the metadata surface.
  /// The previous code copied `sublist(segStart)` - SOS through EOF -
  /// verbatim, which (a) shipped any post-EOI tail the round-4 fix was
  /// meant to drop, and (b) preserved APPn/COM segments placed after the
  /// first SOS. Multi-scan (progressive) JPEGs legitimately interleave
  /// header segments between scans, so post-SOS metadata is *in-stream*
  /// and must be stripped like any other segment. After an SOS header
  /// we therefore walk the entropy-coded data properly - honoring 0xFF00
  /// byte-stuffing and in-stream RST0-7 restart markers - and resume the
  /// segment loop at the next real marker; EOI terminates the whole
  /// stream wherever it occurs.
  ///
  /// (round-10 red finding) A kept MARKER is still not sufficient: the
  /// declared-length payload used to ship verbatim, so a complete
  /// `FF E1 'Exif\0\0' <TIFF>` planted inside a structurally valid DQT
  /// survived - and stayed API-readable, because the exif reader's
  /// segment walk is not entropy-aware and can be steered onto the
  /// plant by fake 16-bit "lengths" planted in the scan data. Every
  /// kept segment's emitted bytes are therefore inspected
  /// (_jpegSegmentCarriesEmbeddedMetadata) for reader landing pads,
  /// metadata signatures and embedded-file magics, and the assembled
  /// output is re-scanned for landing pads that could straddle emit
  /// boundaries - a surviving pad refuses the image content entirely
  /// (bare SOI+EOI).
  static Uint8List _stripJpegMetadataSegments(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return bytes;
    }
    final out = BytesBuilder()..add([0xFF, 0xD8]);
    var i = 2;
    // True while the cursor sits inside entropy-coded scan data (after
    // an SOS header, before the next real marker).
    var inEntropy = false;
    while (i < bytes.length) {
      if (inEntropy) {
        // Entropy-coded data: 0xFF00 is a stuffed literal 0xFF byte and
        // 0xFFD0-0xFFD7 are restart markers - both stay inside the scan.
        // Any other 0xFF-prefixed code is a real marker boundary; the
        // segment loop resumes there (fill 0xFF bytes are skipped by the
        // marker reader, so a boundary at the FIRST 0xFF is correct).
        var j = i;
        while (j < bytes.length) {
          if (bytes[j] != 0xFF) {
            j++;
            continue;
          }
          if (j + 1 >= bytes.length) {
            j++; // trailing lone 0xFF - keep it verbatim and finish
            break;
          }
          final next = bytes[j + 1];
          if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
            j += 2;
            continue;
          }
          break; // real marker begins at j
        }
        out.add(bytes.sublist(i, j));
        i = j;
        inEntropy = false;
        continue;
      }
      final segStart = i;
      if (bytes[i] != 0xFF) {
        // (round-6 red finding) Not at a marker boundary: the stream is
        // malformed here, but copying the remainder verbatim would carry
        // any metadata segment hidden behind the corrupt byte into the
        // "scrubbed" output. Drop the garbage and resync at the next
        // plausible marker instead - fail closed for privacy.
        final next = _nextJpegMarker(bytes, i + 1);
        if (next < 0) break; // no marker left - discard the tail
        i = next;
        continue;
      }
      // Skip 0xFF fill bytes before the marker code.
      while (i + 1 < bytes.length && bytes[i + 1] == 0xFF) {
        i++;
      }
      if (i + 1 >= bytes.length) {
        // Only fill 0xFF bytes remain - no segment can follow.
        break;
      }
      final marker = bytes[i + 1];
      // EOI (0xD9): emit the marker and STOP. Nothing after EOI is
      // image data - (round-4 red finding) a post-EOI tail is the same
      // covert channel the round-3 fix closed for post-IEND PNG bytes,
      // and (round-5) that rule applies at EVERY scan boundary, not
      // only pre-SOS.
      if (marker == 0xD9) {
        out.add(bytes.sublist(segStart, i + 2));
        break;
      }
      // A 0xFF00 pair at a marker boundary means the stream fell out of
      // entropy mode somewhere upstream - malformed. (round-6 red
      // finding) Drop the pair and resync at the next plausible marker;
      // the previous verbatim copy let hidden APPn segments survive.
      if (marker == 0x00) {
        final next = _nextJpegMarker(bytes, i + 2);
        if (next < 0) break;
        i = next;
        continue;
      }
      // Standalone markers without a length field (TEM, RST0-7, SOI).
      if (marker == 0x01 ||
          marker == 0xD8 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        out.add(bytes.sublist(segStart, i + 2));
        i += 2;
        continue;
      }
      // Reserved markers 0x30-0x3F are defined by T.81 to carry NO
      // length field, and they are not decode-relevant. Drop the bare
      // marker and continue at the next bytes - reading a length word
      // here would desync the walk (round-9 red finding: under the
      // allowlist every non-kept marker must still be consumed at its
      // correct width).
      if (marker >= 0x30 && marker <= 0x3F) {
        i += 2;
        continue;
      }
      if (i + 4 > bytes.length) {
        // Truncated length field - too short to contain a segment;
        // discard the remainder.
        break;
      }
      final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
      if (segLen < 2 || i + 2 + segLen > bytes.length) {
        // (round-6 red finding) Malformed length - the declared segment
        // cannot be trusted, but the bytes after it may still form
        // valid segments. Resync past the marker+length word instead of
        // copying a tail that could hide a surviving APPn/COM. Note the
        // resync path applies the SAME keep rule: _nextJpegMarker only
        // repositions the cursor - the marker it lands on is then
        // dispatched through the normal allowlist path below and its
        // payload is dropped unless the marker is decode-relevant
        // (round-8 red finding: an APP2 ICC_PROFILE behind a corrupt
        // length used to survive verbatim this way; round-9 red
        // finding: so did a resync-fabricated reserved marker like
        // FF F0 - the denylist is gone, only allowlisted structure
        // ships).
        final next = _nextJpegMarker(bytes, i + 4);
        if (next < 0) break;
        i = next;
        continue;
      }
      // (round-9 red finding) Keep-dispatch is now a decode-relevant
      // ALLOWLIST - the marker byte alone never suffices to keep a
      // segment, and kept segments that carry a signature must match
      // their canonical payload shape:
      if (marker == 0xE0) {
        // APP0: keep ONLY the canonical JFIF header, re-emitted in its
        // fixed 16-byte form (identifier 'JFIF\0' + version + units +
        // X/Y density + thumbnail dims forced to 0). This drops JFXX
        // and every other APP0 extension - JFIF ext-code 0x10 embeds a
        // COMPLETE inner JPEG stream able to carry its own Exif/GPS
        // APP1 that the exif reader's segment walker cannot see inside
        // - and strips the raw JFIF thumbnail / any declared-length
        // trailer, which was equally uninspected verbatim space.
        // Density fields are preserved, so decode behaviour is
        // unchanged; the output remains a valid JFIF APP0.
        if (_isJfifApp0(bytes, i, segLen)) {
          final app0 = Uint8List.fromList(<int>[
            0xFF,
            0xE0,
            0x00,
            0x10,
            ...bytes.sublist(i + 4, i + 16),
            0x00,
            0x00,
          ]);
          // (round-10 red finding) the version/units/density bytes are
          // attacker-controlled too - drop the APP0 rather than ship a
          // landing pad or signature folded into them.
          if (!_jpegSegmentCarriesEmbeddedMetadata(app0, 0, 0, app0.length)) {
            out.add(app0);
          }
        }
      } else if (marker == 0xEE) {
        // APP14: keep ONLY the canonical 'Adobe' 14-byte transform
        // record decoders consult; any other signature or length is a
        // covert verbatim channel.
        if (_isCanonicalAdobeApp14(bytes, i, segLen) &&
            !_jpegSegmentCarriesEmbeddedMetadata(
                bytes, segStart, i, i + 2 + segLen)) {
          out.add(bytes.sublist(segStart, i + 2 + segLen));
        }
      } else if (_jpegKeptSegmentMarkers.contains(marker) &&
          !_jpegSegmentCarriesEmbeddedMetadata(
              bytes, segStart, i, i + 2 + segLen)) {
        // (round-10 red finding) a kept marker is NOT enough: its
        // declared-length payload used to ship verbatim, so a
        // complete `FF E1 'Exif\0\0' <TIFF>` planted inside a
        // structurally valid DQT survived scrubbing AND stayed
        // readable - the exif reader's segment walk is not
        // entropy-aware and can be steered onto the plant by fake
        // 16-bit "lengths" in the scan data. Kept payloads are now
        // inspected; a segment carrying a landing pad, a metadata
        // signature, or an embedded-file magic is DROPPED (fail
        // closed - losing a table degrades decode; shipping the pad
        // leaks metadata).
        out.add(bytes.sublist(segStart, i + 2 + segLen));
      }
      i += 2 + segLen;
      // SOS (0xDA): whether or not the header was emitted, the bytes
      // that follow are still entropy-coded scan data - walk them as
      // entropy until the next real marker (or EOI).
      if (marker == 0xDA) {
        inEntropy = true;
      }
    }
    final scrubbed = out.toBytes();
    // (round-10 red finding) Last-line defence: a landing pad can
    // STRADDLE emit boundaries - a kept segment ending in a pad
    // prefix (trailing `FF`, `FF E1`, `FF DB`, `FF E1 ?? ?? 'Ex'`, …)
    // is completed by the head of the next emitted piece: entropy
    // bytes are attacker-malleable, and even the next segment's
    // marker/length/payload bytes can supply the 'Exif' tail. The
    // per-segment scan cannot see across the seam, so the assembled
    // stream is scanned once more; if ANY reader landing pad survives
    // the output is a covert carrier - refuse to ship image content
    // and emit a bare SOI+EOI. False positives are effectively
    // impossible: a pad needs ASCII 'Exif'/'Ducky'/'Adobe' at a fixed
    // offset behind an FF-prefixed code, and emitted entropy never
    // contains an unstuffed 0xFF.
    for (var p = 0; p + 1 < scrubbed.length; p++) {
      if (scrubbed[p] == 0xFF &&
          _isJpegReaderLandingPad(scrubbed, p, scrubbed.length)) {
        return Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xD9]);
      }
    }
    return scrubbed;
  }

  /// (round-6 red finding) Forward resync used when the JPEG marker
  /// walk hits malformed structure: returns the index of the next
  /// `0xFF`-prefixed marker candidate at or after [from], or -1 when no
  /// plausible marker remains. `0xFF00` pairs are skipped - at a segment
  /// boundary they are corruption, not a marker. Callers DROP the
  /// skipped region rather than copying it, so a corrupt byte/length can
  /// never smuggle a surviving metadata segment into the output.
  static int _nextJpegMarker(Uint8List bytes, int from) {
    for (var j = from; j + 1 < bytes.length; j++) {
      if (bytes[j] == 0xFF && bytes[j + 1] != 0x00) {
        return j;
      }
    }
    return -1;
  }

  /// PNG ancillary chunk types carrying privacy-sensitive metadata.
  static const Set<String> _pngStrippedChunks = {
    'tEXt', 'zTXt', 'iTXt', // free-text keyword/comment chunks
    'eXIf', // EXIF metadata chunk
    'tIME', // modification timestamp
    'iCCP', // (round-7 red finding) ICC profile - embeds 'desc'/'cprt'
    // author/copyright strings readable by exiftool-class
    // extractors; ancillary, so dropping it is decode-safe.
  };

  /// Removes textual/EXIF ancillary chunks from a PNG stream. Chunks are
  /// self-contained (length+type+data+CRC), so dropping them leaves the
  /// image fully valid - no CRC recomputation needed.
  static Uint8List _stripPngMetadataChunks(Uint8List bytes) {
    const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < 8) return bytes;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != sig[i]) return bytes;
    }
    final out = BytesBuilder()..add(sig);
    var i = 8;
    while (i + 8 <= bytes.length) {
      final len = (bytes[i] << 24) |
          (bytes[i + 1] << 16) |
          (bytes[i + 2] << 8) |
          bytes[i + 3];
      final type = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
      final end = i + 12 + len;
      if (len < 0 || end > bytes.length) {
        // (round-7 red finding) Malformed chunk - the declared length
        // cannot be trusted, and the previous code copied the whole
        // remainder VERBATIM, shipping complete eXIf/tEXt/iTXt chunks
        // hidden behind the fault inside "scrubbed" output - the same
        // fail-open class the round-6 JPEG resync closed. Drop the
        // unverifiable tail and stop: the emitted prefix stays
        // well-formed, and no metadata-bearing chunk can ride through.
        break;
      }
      if (!_pngStrippedChunks.contains(type)) {
        out.add(bytes.sublist(i, end));
      }
      i = end;
      if (type == 'IEND') break;
    }
    // (round-3 red finding) bytes after IEND are NOT part of the PNG
    // stream - ancillary chunks smuggled past the terminator previously
    // rode through verbatim and survived "scrubbing". Drop them. The
    // malformed-chunk bail-out above likewise drops the unverifiable
    // tail now (round-7 red finding) - no uninspected bytes ever reach
    // the output.
    return out.toBytes();
  }

  /// Get file type from bytes
  String? detectFileType(Uint8List bytes) {
    if (bytes.length < 12) return null;

    // JPEG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    // PNG
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }

    // HEIC/HEIF
    if (bytes.length > 11) {
      final str = String.fromCharCodes(bytes.sublist(4, 12));
      if (str.contains('ftyp') &&
          (str.contains('heic') || str.contains('heif'))) {
        return 'image/heic';
      }
    }

    // PDF
    if (bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'application/pdf';
    }

    // MP4
    if (bytes.length > 11) {
      final str = String.fromCharCodes(bytes.sublist(4, 8));
      if (str == 'ftyp') {
        return 'video/mp4';
      }
    }

    return null;
  }

  /// Check if scrubbing is supported for this file type.
  ///
  /// (round-3 red finding) advertises ONLY formats the scrub switch
  /// actually rewrites - HEIC/HEIF/TIFF were previously claimed
  /// supported but fell through untouched, silently "scrubbing"
  /// nothing. Claiming support for an unhandled format is worse than
  /// refusing: callers would ship the file believing it was cleaned.
  bool isSupportedType(String mimeType) {
    return [
      'image/jpeg',
      'image/png',
    ].contains(mimeType.toLowerCase());
  }
}
