import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/media/spatial_media_service.dart';

void main() {
  group('Spatial 3D Media Parser Tests', () {
    late SpatialMediaService spatialService;

    setUp(() {
      spatialService = SpatialMediaService();
    });

    test('parses glTF Binary (GLB) header', () {
      final glb = Uint8List(20);
      glb[0] = 0x67; // 'g'
      glb[1] = 0x6C; // 'l'
      glb[2] = 0x54; // 'T'
      glb[3] = 0x46; // 'F'
      glb[4] = 2;    // version 2
      glb[8] = 1024; // length 1024
      glb[12] = 512; // JSON length

      final meta = spatialService.parseGlbHeader(glb);
      expect(meta.version, equals(2));
      expect(meta.byteLength, equals(1024));
      expect(meta.jsonLength, equals(512));
    });
  });
}
