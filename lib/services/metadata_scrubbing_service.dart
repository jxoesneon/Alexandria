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

  ScrubbingResult({
    required this.scrubbedBytes,
    required this.newCid,
    required this.removedFields,
    required this.originalSize,
    required this.scrubbedSize,
  });

  bool get wasModified => removedFields.isNotEmpty;
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

  MetadataScrubbingService(this._cidService);

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

  /// Scrub metadata from image bytes
  ///
  /// Note: Full EXIF stripping requires native code. This implementation
  /// identifies what would be removed. For actual removal, the app should
  /// use a native library like image_editor or native code.
  Future<ScrubbingResult> scrubMetadata(
    Uint8List bytes, {
    ScrubbingOptions options = ScrubbingOptions.privacy,
  }) async {
    // Detect what fields exist
    final data = await readExifFromBytes(bytes);
    final fieldsToRemove = options.fieldsToRemove;
    final removedFields = <String>[];

    for (final field in fieldsToRemove) {
      if (data.containsKey(field)) {
        removedFields.add(field);
      }
    }

    // For now, we return the original bytes since full EXIF stripping
    // requires native code. In production, use image_editor or native.
    // The CID is recalculated to show what the new CID would be.
    final scrubbedBytes = bytes; // Placeholder - would be stripped bytes
    final newCid = _cidService.cidFromBytes(scrubbedBytes);

    return ScrubbingResult(
      scrubbedBytes: scrubbedBytes,
      newCid: newCid,
      removedFields: removedFields,
      originalSize: bytes.length,
      scrubbedSize: scrubbedBytes.length,
    );
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

  /// Check if scrubbing is supported for this file type
  bool isSupportedType(String mimeType) {
    return [
      'image/jpeg',
      'image/png',
      'image/heic',
      'image/heif',
      'image/tiff',
    ].contains(mimeType.toLowerCase());
  }
}
