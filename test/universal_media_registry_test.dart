import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/universal_media_registry.dart';
import 'package:alexandria/services/external_player_service.dart';

void main() {
  group('UniversalMediaRegistry Tests', () {
    late ProviderContainer container;
    late UniversalMediaRegistry registry;

    setUp(() {
      container = ProviderContainer();
      registry = container.read(universalMediaRegistryProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('resolves academic file extensions correctly', () {
      final texDesc = registry.resolveExtension('tex');
      expect(texDesc.domain, equals(MediaDomain.academicAndScience));
      expect(texDesc.preferredApp, equals(SupportedApp.codeEditor));

      final typDesc = registry.resolveExtension('.typ');
      expect(typDesc.domain, equals(MediaDomain.academicAndScience));
    });

    test('resolves audio and spatial media extensions', () {
      final flacDesc = registry.resolveExtension('flac');
      expect(flacDesc.domain, equals(MediaDomain.audioAndAcoustic));
      expect(flacDesc.preferredApp, equals(SupportedApp.vlc));

      final glbDesc = registry.resolveExtension('glb');
      expect(glbDesc.domain, equals(MediaDomain.visualArtAndSpatial));
      expect(glbDesc.preferredApp, equals(SupportedApp.blender));
    });

    test('falls back to generic binary for unknown extensions', () {
      final unknown = registry.resolveExtension('xyz123');
      expect(unknown.domain, equals(MediaDomain.genericBinary));
      expect(unknown.preferredApp, equals(SupportedApp.systemDefault));
    });
  });
}
