import 'dart:convert';
import 'dart:io';
import 'package:exif/exif.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final metadataServiceProvider = Provider((ref) => MetadataExtractionService());

class MetadataExtractionService {
  Future<Map<String, dynamic>> extractMetadata(PlatformFile file) async {
    final metadata = <String, dynamic>{};

    // Basic File Info
    metadata['size_bytes'] = file.size;
    metadata['format'] = file.extension?.toLowerCase() ?? 'unknown';

    // Image Metadata (EXIF)
    if ([
      'jpg',
      'jpeg',
      'png',
      'webp',
      'heic',
    ].contains(file.extension?.toLowerCase())) {
      try {
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        final tags = await readExifFromBytes(bytes);

        // Resolution
        if (tags.containsKey('Image ImageWidth') &&
            tags.containsKey('Image ImageLength')) {
          metadata['resolution'] =
              "${tags['Image ImageWidth']}x${tags['Image ImageLength']}";
        } else if (tags.containsKey('EXIF ExifImageWidth') &&
            tags.containsKey('EXIF ExifImageLength')) {
          metadata['resolution'] =
              "${tags['EXIF ExifImageWidth']}x${tags['EXIF ExifImageLength']}";
        }

        // Camera Model
        if (tags.containsKey('Image Model')) {
          metadata['camera_model'] = tags['Image Model'].toString();
        }

        // Date Taken
        if (tags.containsKey('Image DateTime')) {
          metadata['date_taken'] = tags['Image DateTime'].toString();
        } else if (tags.containsKey('EXIF DateTimeOriginal')) {
          metadata['date_taken'] = tags['EXIF DateTimeOriginal'].toString();
        }

        // Tech Specs (ISO, Aperture, Shutter, Focal Length)
        if (tags.containsKey('EXIF ISOSpeedRatings')) {
          metadata['iso'] = tags['EXIF ISOSpeedRatings'].toString();
        }
        if (tags.containsKey('EXIF FNumber')) {
          metadata['aperture'] = "f/${tags['EXIF FNumber']}";
        }
        if (tags.containsKey('EXIF ExposureTime')) {
          metadata['shutter_speed'] = tags['EXIF ExposureTime'].toString();
        }
        if (tags.containsKey('EXIF FocalLength')) {
          metadata['focal_length'] = "${tags['EXIF FocalLength']}mm";
        }

        // GPS (Simplified presence check for now, decoding is complex)
        if (tags.containsKey('GPS GPSLatitude') &&
            tags.containsKey('GPS GPSLongitude')) {
          metadata['location'] = 'GPS Data Present';
        }
      } catch (e) {
        debugPrint('Error reading EXIF: $e');
      }
    }

    // Code & Dataset Analysis (Text based)
    final ext = file.extension?.toLowerCase();
    if ([
      'dart',
      'py',
      'js',
      'html',
      'css',
      'java',
      'c',
      'cpp',
      'h',
      'md',
      'csv',
      'json',
      'txt',
      'xml',
      'yaml',
      'yml',
    ].contains(ext)) {
      try {
        // We use a stream to avoid loading huge files into memory
        final f = File(file.path!);
        int lines = 0;
        await f
            .openRead()
            .transform(
              const SystemEncoding().decoder,
            ) // Use system encoding (usually UTF-8)
            .transform(const LineSplitter())
            .forEach((_) => lines++);

        if (['csv', 'json', 'xml'].contains(ext)) {
          // For datasets, line count is a proxy for row count
          // CSV: lines = rows (approx)
          // JSON: rough estimate, ideally we'd parse, but for MVP this is safe
          metadata['row_count'] = lines;
        } else {
          // For code, it's dependencies (approx lines)
          // We map 'dependencies' field to lines count specifically for the simplified form
          metadata['dependencies'] = lines;
        }
      } catch (e) {
        debugPrint('Error reading text file stats: $e');
      }
    }

    return metadata;
  }
}
