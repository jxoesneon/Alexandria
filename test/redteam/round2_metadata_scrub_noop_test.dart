// RED TEAM PoC — MetadataScrubbingService.scrubMetadata is a no-op
// that REPORTS successful removal.
//
// lib/services/metadata_scrubbing_service.dart:238 returns the input
// bytes verbatim (`final scrubbedBytes = bytes; // Placeholder`) while
// still populating `removedFields` with every sensitive EXIF tag it
// detected and computing a "new" CID over the unchanged payload.
// A caller that trusts the contract (Spec §11.4 anonymity) publishes
// GPS/device/author metadata it believes was stripped — a silent
// privacy failure, worse than refusing to scrub at all.
//
// Asserts the SECURE expectation: fields reported as removed must be
// undetectable in the returned bytes. Failure marks a live
// claims-vs-reality divergence.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/cid_service.dart';
import 'package:alexandria/services/metadata_scrubbing_service.dart';

/// Minimal JPEG carrying a real EXIF APP1 segment with
/// Make/Model/Artist — enough for package:exif to parse.
Uint8List _buildExifJpeg() {
  final tiff = BytesBuilder();
  // TIFF header: little-endian, magic 42, IFD0 at offset 8.
  tiff.add([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]);
  tiff.add([0x03, 0x00]); // 3 IFD entries
  const strBase = 8 + 2 + 3 * 12 + 4;
  final make = 'EvilCam\x00'.codeUnits;
  final model = 'X-1000\x00\x00'.codeUnits;
  final artist = 'Secret Author\x00'.codeUnits;
  void entry(int tag, List<int> s, int off) {
    tiff.add([tag & 0xFF, tag >> 8, 0x02, 0x00]);
    tiff.add([s.length & 0xFF, 0, 0, 0]);
    tiff.add([off & 0xFF, (off >> 8) & 0xFF, 0, 0]);
  }

  entry(0x010F, make, strBase); // Image Make
  entry(0x0110, model, strBase + make.length); // Image Model
  entry(0x013B, artist, strBase + make.length + model.length); // Artist
  tiff.add([0, 0, 0, 0]); // no next IFD
  tiff.add(make);
  tiff.add(model);
  tiff.add(artist);

  final tiffBytes = tiff.toBytes();
  final jpeg = BytesBuilder();
  jpeg.add([0xFF, 0xD8]);
  final app1Len = 2 + 6 + tiffBytes.length;
  jpeg.add([0xFF, 0xE1, (app1Len >> 8) & 0xFF, app1Len & 0xFF]);
  jpeg.add('Exif\x00\x00'.codeUnits);
  jpeg.add(tiffBytes);
  jpeg.add([0xFF, 0xD9]);
  return jpeg.toBytes();
}

void main() {
  test('scrubbed output must not still carry the reported-removed EXIF',
      () async {
    final svc = MetadataScrubbingService(CidService());
    final original = _buildExifJpeg();

    // Sanity: the sensitive fields are really there.
    final detected = await svc.detectSensitiveFields(original);
    expect(detected, containsAll(['Image Make', 'Image Model', 'Image Artist']));

    final result =
        await svc.scrubMetadata(original, options: ScrubbingOptions.full);

    // The service CLAIMS removal...
    expect(result.removedFields, isNotEmpty,
        reason: 'fixture should advertise removed fields for this test');

    // ...so the returned bytes must no longer expose them.
    final stillPresent =
        await svc.detectSensitiveFields(result.scrubbedBytes);
    expect(stillPresent, isEmpty,
        reason:
            'removedFields=${result.removedFields} but the scrubbed bytes '
            'still expose $stillPresent — scrubMetadata returned the '
            'original payload unchanged (placeholder implementation) while '
            'reporting a successful scrub. Publishing result.scrubbedBytes '
            'leaks every field the user asked to strip.');

    // Byte-identity makes the leak undeniable.
    expect(result.scrubbedBytes, isNot(equals(original)),
        reason: 'scrubbedBytes is byte-identical to the input');
  });

  test('newCid over unchanged bytes is the SAME cid — no scrub happened',
      () async {
    final cidService = CidService();
    final svc = MetadataScrubbingService(cidService);
    final original = _buildExifJpeg();
    final result =
        await svc.scrubMetadata(original, options: ScrubbingOptions.full);

    // If scrubbing truly removed fields the digest would differ.
    expect(result.newCid, isNot(cidService.cidFromBytes(original)),
        reason:
            'the "post-scrub" CID equals the pre-scrub CID — the output '
            'payload is byte-identical, yet the API reports '
            'wasModified=${result.wasModified}');
  });
}
