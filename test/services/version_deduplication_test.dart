import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/services/seed/starter_seed_service.dart';
import 'package:alexandria/providers/library_providers.dart';

void main() {
  group('Version Deduplication & Multi-Edition Architecture (ALX-001 §3)', () {
    test(
        'ingests multi-version documents under single manifest with zero catalog duplication',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final db = container.read(databaseProvider);
      final seedService = container.read(starterSeedServiceProvider);

      // Ingest the 3 landmark open science documents (Einstein, Watson & Crick, Turing)
      final count = await seedService.ingestSeedPack('open-science-landmarks');
      expect(count, 3);

      // 1. Manifests Count: Must be exactly 3 (zero card duplication in library)
      final manifests = await db.getAllManifests();
      expect(manifests.length, 3,
          reason: 'Each intellectual work must occupy exactly 1 catalog entry');

      // 2. Content Versions Count: Must be exactly 6 (each has 1 unabridged + 1 executive brief)
      final allVersions = await db.select(db.contentVersions).get();
      expect(allVersions.length, 6,
          reason:
              'Each work must link both an unabridged and a brief CIDv1 version');

      // 3. Inspect Einstein 1905 specifically
      final einsteinManifest =
          manifests.firstWhere((m) => m.title.contains('Photoelectric'));
      final einsteinVersions =
          await db.getVersionsForManifest(einsteinManifest.id);
      expect(einsteinVersions.length, 2);

      final unabridgedVersion =
          einsteinVersions.firstWhere((v) => v.format == 'md-unabridged');
      final briefVersion =
          einsteinVersions.firstWhere((v) => v.format == 'md-brief');

      // Cryptographic uniqueness
      expect(unabridgedVersion.cid, isNot(equals(briefVersion.cid)),
          reason: 'Different text payloads generate distinct Merkle DAG CIDs');
      expect(unabridgedVersion.sizeBytes, greaterThan(10000),
          reason: 'Unabridged text is ~12 KB');
      expect(briefVersion.sizeBytes, lessThan(3000),
          reason: 'Executive brief is ~2 KB');

      // 4. Library Dashboard Stats: Total items remains 3, total size aggregates all versions
      final dashboardStats =
          await container.read(libraryDashboardProvider.future);
      expect(dashboardStats.totalItems, 3,
          reason: 'Dashboard displays unique catalog works, not raw CIDs');

      // 5. Version Resolution & Dynamic Switching in Reader
      // A) Default resolves unabridged text
      final defaultDoc = await container
          .read(currentDocumentProvider(einsteinManifest.uuid).future);
      expect(defaultDoc.format, 'md-unabridged');
      expect(
          defaultDoc.content,
          contains(
              'Concerning a Difficulty with the Theory of "Black-Body Radiation"'));

      // B) User switches to Executive Brief edition
      container
          .read(activeVersionCidProvider(einsteinManifest.uuid).notifier)
          .state = briefVersion.cid;

      final briefDoc = await container
          .read(currentDocumentProvider(einsteinManifest.uuid).future);
      expect(briefDoc.format, 'md-brief');
      expect(
          briefDoc.content,
          contains(
              'Executive Brief: On the Photoelectric Effect & Light Quanta'));
      expect(briefDoc.content,
          contains('Catalog Edition: Executive Summary & Core Formulations'));
    });
  });
}
