import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/services/seed/starter_seed_service.dart';

void main() {
  group('Seed ingestion - network-sourced, deduplicated', () {
    test('ingests resolvable docs, dedupes on re-ingest, skips unresolvable',
        () async {
      final container = ProviderContainer(overrides: [
        starterSeedServiceProvider.overrideWith((ref) => StarterSeedService(
              ref,
              docFetcher: (doc) async => doc.id == 'doi_turing_1936'
                  ? null // simulates no reachable OA/swarm copy
                  : Uint8List.fromList('content of ${doc.id}'.codeUnits),
            )),
      ]);
      addTearDown(container.dispose);
      final db = container.read(databaseProvider);
      final seedService = container.read(starterSeedServiceProvider);

      final first = await seedService.ingestSeedPack('open-science-landmarks');
      expect(first.ingested, 2);
      expect(first.deduped, 0);
      expect(first.skipped.map((s) => s.docId), contains('doi_turing_1936'));

      final manifests = await db.getAllManifests();
      expect(manifests.length, 2,
          reason: 'one manifest per resolved work, never a phantom');

      final einstein =
          manifests.firstWhere((m) => m.title.contains('Photoelectric'));
      expect(einstein.metadata, contains('"seedDoc":"doi_einstein_1905"'));
      expect(einstein.metadata, contains('"sourcedFrom":"network"'));
      final versions = await db.getVersionsForManifest(einstein.id);
      expect(versions.length, 1);
      expect(versions.single.format, 'pdf');

      // Re-ingest: everything dedupes by seedDoc marker - the catalog
      // never grows a duplicate manifest for the same work.
      final second = await seedService.ingestSeedPack('open-science-landmarks');
      expect(second.ingested, 0);
      expect(second.deduped, 2);
      expect(second.skipped.map((s) => s.docId), contains('doi_turing_1936'));
      expect((await db.getAllManifests()).length, 2);
    });

    test('all-unresolvable pack produces zero manifests honestly', () async {
      final container = ProviderContainer(overrides: [
        starterSeedServiceProvider.overrideWith(
            (ref) => StarterSeedService(ref, docFetcher: (doc) async => null)),
      ]);
      addTearDown(container.dispose);
      final db = container.read(databaseProvider);
      final seedService = container.read(starterSeedServiceProvider);

      final result = await seedService.ingestSeedPack('classical-commons');
      expect(result.ingested, 0);
      expect(result.skipped, hasLength(2));
      expect(await db.getAllManifests(), isEmpty);
    });
  });
}
