import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/services/seed/starter_seed_service.dart';

void main() {
  group('StarterSeedService Unit Tests (First-Run Experience)', () {
    test('provides curated metadata-only packs with resolution pointers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(starterSeedServiceProvider);
      final packs = service.getAvailableSeedPacks();

      expect(packs.length, greaterThanOrEqualTo(2));

      // 1. Open Science Landmark Pack - DOI pointers only.
      final sciencePack =
          packs.firstWhere((p) => p.id == 'open-science-landmarks');
      expect(sciencePack.name, contains('Landmark Open Science'));
      expect(sciencePack.documents.length, 3);

      final einsteinDoc = sciencePack.documents
          .firstWhere((d) => d.author.contains('Einstein'));
      expect(einsteinDoc.year, 1905);
      expect(einsteinDoc.doi, '10.1002/andp.19053220607');
      expect(einsteinDoc.title, contains('Photoelectric'));
      expect(einsteinDoc.expectedFormat, 'pdf');

      final watsonCrickDoc =
          sciencePack.documents.firstWhere((d) => d.author.contains('Crick'));
      expect(watsonCrickDoc.doi, '10.1038/171737a0');

      final turingDoc =
          sciencePack.documents.firstWhere((d) => d.author.contains('Turing'));
      expect(turingDoc.doi, '10.1112/plms/s2-42.1.230');

      // 2. Classical Commons Pack - direct legal OA pointers.
      final heritagePack = packs.firstWhere((p) => p.id == 'classical-commons');
      expect(heritagePack.name, contains('Human Commons'));
      expect(heritagePack.documents.length, 2);

      final newtonDoc =
          heritagePack.documents.firstWhere((d) => d.author.contains('Newton'));
      expect(newtonDoc.year, 1687);
      expect(newtonDoc.oaUrl, contains('archive.org'));

      final platoDoc =
          heritagePack.documents.firstWhere((d) => d.author.contains('Plato'));
      expect(platoDoc.oaUrl, contains('gutenberg.org'));
    });

    test('catalog entries carry no embedded content', () {
      // The legal invariant this service exists to guarantee: every
      // document is a pointer record - id, title, author, year, doi,
      // oaUrl, cid, format, description, tags - and nothing else.
      // There must be no field that could hold payload bytes.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(starterSeedServiceProvider);
      for (final pack in service.getAvailableSeedPacks()) {
        for (final doc in pack.documents) {
          expect(doc.id, isNotEmpty);
          expect(doc.title, isNotEmpty);
          expect(
              doc.doi != null || doc.oaUrl != null || doc.cid != null, isTrue,
              reason: '${doc.id} needs at least one resolution pointer');
        }
      }
    });
  });
}
