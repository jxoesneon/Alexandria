import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/ipfs_service.dart';
import 'package:alexandria/services/preservation_service.dart';
import 'package:alexandria/ui/home_screen.dart';
import 'package:alexandria/ui/widgets/glass_card.dart';

class _FakeIpfsService implements IpfsService {
  final Set<String> _cids;
  _FakeIpfsService([this._cids = const {'bafy_1', 'bafy_2'}]);

  @override
  Set<String> get pinnedCids => _cids;

  @override
  int get storedBytes => 0;

  @override
  int get swarmPeerCount => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePreservationService implements PreservationService {
  final HealthStatus status;
  _FakePreservationService([this.status = HealthStatus.healthy]);

  @override
  Future<HealthStatus> checkContentHealth(String cid) async => status;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeScreen Tests', () {
    testWidgets('renders Alexandria header, health status, and action buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            preservationServiceProvider
                .overrideWithValue(_FakePreservationService()),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      expect(find.text('Alexandria'), findsOneWidget);
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Your Decentralized Library'), findsOneWidget);
      expect(find.text('Add to Library'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(GlassCard), findsWidgets);
      expect(find.text('All Content Healthy'), findsOneWidget);
      expect(find.text('All artifacts preserved'), findsOneWidget);
      expect(find.text('Recent Additions'), findsOneWidget);
      // Recent additions are provider-driven: the hermetic in-memory
      // database holds no manifests, so the honest empty state shows.
      expect(
        find.text(
            'No documents in the library yet. Add your first artifact to see it here.'),
        findsOneWidget,
      );
    });

    testWidgets('renders endangered and lost health statuses', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ipfsServiceProvider
                .overrideWithValue(_FakeIpfsService({'bafy_lost'})),
            preservationServiceProvider
                .overrideWithValue(_FakePreservationService(HealthStatus.lost)),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('1 Content Lost'), findsOneWidget);
      expect(find.text('Preservation Health'), findsOneWidget);
      expect(find.text('Lost'), findsOneWidget);
    });

    testWidgets('taps search icon and view all to navigate', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ipfsServiceProvider.overrideWithValue(_FakeIpfsService()),
            preservationServiceProvider
                .overrideWithValue(_FakePreservationService()),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      expect(find.text('Discovery & Search'), findsOneWidget);

      // Pop back
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // Tap View All
      await tester.tap(find.text('View All'));
      await tester.pumpAndSettle();
      expect(find.text('Discovery & Search'), findsOneWidget);
    });
  });
}
