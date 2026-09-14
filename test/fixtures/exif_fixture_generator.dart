import 'dart:typed_data';

Uint8List buildSampleExifJpeg({
  bool useExifResolution = false,
  bool useExifDateTime = false,
}) {
  final ifd0Tags = <int, dynamic>{};
  if (!useExifResolution) {
    ifd0Tags[0x0100] = 1920; // ImageWidth
    ifd0Tags[0x0101] = 1080; // ImageLength
  }
  ifd0Tags[0x010F] = 'Sony\x00';
  ifd0Tags[0x0110] = 'A7R IV\x00';
  if (!useExifDateTime) {
    ifd0Tags[0x0132] = '2023:05:01 12:00:00\x00';
  }
  ifd0Tags[0x013B] = 'Alexandria\x00';

  final exifTags = <int, dynamic>{};
  if (useExifResolution) {
    exifTags[0xA002] = 3840; // ExifImageWidth
    exifTags[0xA003] = 2160; // ExifImageLength
  }
  if (useExifDateTime) {
    exifTags[0x9003] = '2023:05:01 12:00:00\x00'; // DateTimeOriginal
  }
  exifTags[0x8827] = 800; // ISOSpeedRatings
  exifTags[0x829D] = [28, 10]; // FNumber
  exifTags[0x829A] = [1, 500]; // ExposureTime
  exifTags[0x920A] = [85, 1]; // FocalLength

  final gpsTags = <int, dynamic>{
    0x0002: [
      [37, 1],
      [46, 1],
      [29, 1],
    ],
    0x0004: [
      [122, 1],
      [25, 1],
      [10, 1],
    ],
  };

  final ifd0Count = ifd0Tags.length + 2;
  final ifd0Size = 2 + (ifd0Count * 12) + 4;
  final exifOffset = 8 + ifd0Size;

  final exifCount = exifTags.length;
  final exifSize = 2 + (exifCount * 12) + 4;
  final gpsOffset = exifOffset + exifSize;

  final gpsCount = gpsTags.length;
  final gpsSize = 2 + (gpsCount * 12) + 4;
  final dataOffset = gpsOffset + gpsSize;

  final tiffBuffer = ByteData(4096);
  tiffBuffer.setUint8(0, 0x49); // 'I'
  tiffBuffer.setUint8(1, 0x49); // 'I'
  tiffBuffer.setUint16(2, 42, Endian.little);
  tiffBuffer.setUint32(4, 8, Endian.little);

  int currentDataOffset = dataOffset;

  void writeString(int offset, String str) {
    final bytes = str.codeUnits;
    for (int i = 0; i < bytes.length; i++) {
      tiffBuffer.setUint8(offset + i, bytes[i]);
    }
  }

  void writeRational(int offset, int num, int den) {
    tiffBuffer.setUint32(offset, num, Endian.little);
    tiffBuffer.setUint32(offset + 4, den, Endian.little);
  }

  // Write IFD0
  tiffBuffer.setUint16(8, ifd0Count, Endian.little);
  int entryOffset = 10;
  final sortedIfd0Keys = [...ifd0Tags.keys, 0x8769, 0x8825]..sort();

  for (final tag in sortedIfd0Keys) {
    tiffBuffer.setUint16(entryOffset, tag, Endian.little);
    if (tag == 0x8769) {
      tiffBuffer.setUint16(entryOffset + 2, 4, Endian.little);
      tiffBuffer.setUint32(entryOffset + 4, 1, Endian.little);
      tiffBuffer.setUint32(entryOffset + 8, exifOffset, Endian.little);
    } else if (tag == 0x8825) {
      tiffBuffer.setUint16(entryOffset + 2, 4, Endian.little);
      tiffBuffer.setUint32(entryOffset + 4, 1, Endian.little);
      tiffBuffer.setUint32(entryOffset + 8, gpsOffset, Endian.little);
    } else {
      final val = ifd0Tags[tag];
      if (val is int) {
        tiffBuffer.setUint16(entryOffset + 2, 3, Endian.little);
        tiffBuffer.setUint32(entryOffset + 4, 1, Endian.little);
        tiffBuffer.setUint16(entryOffset + 8, val, Endian.little);
        tiffBuffer.setUint16(entryOffset + 10, 0, Endian.little);
      } else if (val is String) {
        final len = val.length;
        tiffBuffer.setUint16(entryOffset + 2, 2, Endian.little);
        tiffBuffer.setUint32(entryOffset + 4, len, Endian.little);
        if (len <= 4) {
          writeString(entryOffset + 8, val);
        } else {
          tiffBuffer.setUint32(
            entryOffset + 8,
            currentDataOffset,
            Endian.little,
          );
          writeString(currentDataOffset, val);
          currentDataOffset += (len + 1);
        }
      }
    }
    entryOffset += 12;
  }
  tiffBuffer.setUint32(entryOffset, 0, Endian.little);

  // Write Exif IFD
  tiffBuffer.setUint16(exifOffset, exifCount, Endian.little);
  entryOffset = exifOffset + 2;
  final sortedExifKeys = exifTags.keys.toList()..sort();
  for (final tag in sortedExifKeys) {
    tiffBuffer.setUint16(entryOffset, tag, Endian.little);
    final val = exifTags[tag];
    if (val is int) {
      if (tag == 0xA002 || tag == 0xA003) {
        tiffBuffer.setUint16(entryOffset + 2, 4, Endian.little);
        tiffBuffer.setUint32(entryOffset + 4, 1, Endian.little);
        tiffBuffer.setUint32(entryOffset + 8, val, Endian.little);
      } else {
        tiffBuffer.setUint16(entryOffset + 2, 3, Endian.little);
        tiffBuffer.setUint32(entryOffset + 4, 1, Endian.little);
        tiffBuffer.setUint16(entryOffset + 8, val, Endian.little);
        tiffBuffer.setUint16(entryOffset + 10, 0, Endian.little);
      }
    } else if (val is String) {
      final len = val.length;
      tiffBuffer.setUint16(entryOffset + 2, 2, Endian.little);
      tiffBuffer.setUint32(entryOffset + 4, len, Endian.little);
      if (len <= 4) {
        writeString(entryOffset + 8, val);
      } else {
        tiffBuffer.setUint32(
          entryOffset + 8,
          currentDataOffset,
          Endian.little,
        );
        writeString(currentDataOffset, val);
        currentDataOffset += (len + 1);
      }
    } else if (val is List<int>) {
      tiffBuffer.setUint16(entryOffset + 2, 5, Endian.little);
      tiffBuffer.setUint32(entryOffset + 4, 1, Endian.little);
      tiffBuffer.setUint32(entryOffset + 8, currentDataOffset, Endian.little);
      writeRational(currentDataOffset, val[0], val[1]);
      currentDataOffset += 8;
    }
    entryOffset += 12;
  }
  tiffBuffer.setUint32(entryOffset, 0, Endian.little);

  // Write GPS IFD
  tiffBuffer.setUint16(gpsOffset, gpsCount, Endian.little);
  entryOffset = gpsOffset + 2;
  final sortedGpsKeys = gpsTags.keys.toList()..sort();
  for (final tag in sortedGpsKeys) {
    tiffBuffer.setUint16(entryOffset, tag, Endian.little);
    final val = gpsTags[tag] as List<List<int>>;
    tiffBuffer.setUint16(entryOffset + 2, 5, Endian.little);
    tiffBuffer.setUint32(entryOffset + 4, val.length, Endian.little);
    tiffBuffer.setUint32(entryOffset + 8, currentDataOffset, Endian.little);
    for (final rat in val) {
      writeRational(currentDataOffset, rat[0], rat[1]);
      currentDataOffset += 8;
    }
    entryOffset += 12;
  }
  tiffBuffer.setUint32(entryOffset, 0, Endian.little);

  final tiffBytes = tiffBuffer.buffer.asUint8List(0, currentDataOffset);

  final app1Payload = BytesBuilder();
  app1Payload.add([0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
  app1Payload.add(tiffBytes);
  final app1Length = app1Payload.length + 2;

  final jpeg = BytesBuilder();
  jpeg.add([0xFF, 0xD8]);
  jpeg.add([0xFF, 0xE1]);
  jpeg.add([(app1Length >> 8) & 0xFF, app1Length & 0xFF]);
  jpeg.add(app1Payload.toBytes());
  jpeg.add([0xFF, 0xD9]);

  return jpeg.toBytes();
}
