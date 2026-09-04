import 'dart:async';

import 'package:alexandria/models/network_models.dart';
import 'package:alexandria/providers/network_providers.dart';
import 'package:alexandria/services/network_overview_service.dart';
import 'package:alexandria/ui/network/sync_conflict_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNetworkOverviewService extends NetworkOverviewService {
  FakeNetworkOverviewService(super.ref);

  final _syncController = StreamController<SyncProgress>.broadcast();

  bool manualSyncCalled = false;
  Conflict? resolvedConflict;

  @override
  Stream<SyncProgress> watchSyncProgress() async* {
    yield SyncProgress(
      overallProgress: 0.45,
      activeTransfers: const [
        Transfer(
          name: 'metadata_delta_12.zip',
          bytesTransferred: 450000,
          totalBytes: 1000000,
        ),
        Transfer(
          name: 'document_crdt_patch.json',
          bytesTransferred: 120000,
          totalBytes: 300000,
        ),
      ],
      pendingConflicts: [
        Conflict(
          id: 'conflict-1',
          documentName: 'Research Notes',
          localVersion: 'v2.1.0',
          remoteVersion: 'v2.1.1',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        Conflict(
          id: 'conflict-2',
          documentName: 'Draft Chapter',
          localVersion: 'v1.0.0',
          remoteVersion: 'v1.0.2',
          timestamp: DateTime.now().subtract(const Duration(minutes: 12)),
        ),
      ],
    );
    yield* _syncController.stream;
  }

  @override
  Future<void> triggerManualSync() async {
    manualSyncCalled = true;
  }

  @override
  Future<bool> resolveConflict(Conflict conflict) async {
    resolvedConflict = conflict;
    _syncController.add(
      const SyncProgress(
        overallProgress: 1.0,
        activeTransfers: [],
        pendingConflicts: [],
      ),
    );
    return true;
  }

  @override
  void dispose() {
    _syncController.close();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SyncConflictScreen renders sync progress and conflicts',
      (tester) async {
    late FakeNetworkOverviewService fake;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith((ref) {
            fake = FakeNetworkOverviewService(ref);
            return fake;
          }),
        ],
        child: const MaterialApp(
          home: SyncConflictScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Sync & Conflict Resolution'), findsOneWidget);
    expect(find.text('45% complete'), findsOneWidget);
    expect(find.text('metadata_delta_12.zip'), findsOneWidget);
    expect(find.text('document_crdt_patch.json'), findsOneWidget);
    expect(find.text('Research Notes'), findsOneWidget);
    expect(find.text('Draft Chapter'), findsOneWidget);
  });

  testWidgets('SyncConflictScreen triggers manual sync', (tester) async {
    late FakeNetworkOverviewService fake;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith((ref) {
            fake = FakeNetworkOverviewService(ref);
            return fake;
          }),
        ],
        child: const MaterialApp(
          home: SyncConflictScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Start manual sync'));
    await tester.pump();

    expect(fake.manualSyncCalled, isTrue);
  });

  testWidgets('SyncConflictScreen resolves a conflict', (tester) async {
    late FakeNetworkOverviewService fake;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          networkOverviewServiceProvider.overrideWith((ref) {
            fake = FakeNetworkOverviewService(ref);
            return fake;
          }),
        ],
        child: const MaterialApp(
          home: SyncConflictScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.ensureVisible(find.text('Resolve').first);
    await tester.tap(find.text('Resolve').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(fake.resolvedConflict, isNotNull);
    expect(find.text('Resolved Research Notes'), findsOneWidget);
  });

  testWidgets('SyncConflictScreen handles empty transfers and conflicts',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncProgressProvider.overrideWith(
            (ref) => Stream.value(
              const SyncProgress(
                overallProgress: 1.0,
                activeTransfers: [],
                pendingConflicts: [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: SyncConflictScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('No active transfers'), findsOneWidget);
    expect(find.text('No pending conflicts'), findsOneWidget);
  });
}
