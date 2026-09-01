import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('SyncService P2P PubSub Queue Tests', () {
    late ProviderContainer container;
    late SyncService syncService;

    setUp(() {
      container = ProviderContainer();
      syncService = container.read(syncServiceProvider);
    });

    tearDown(() {
      syncService.dispose();
      container.dispose();
    });

    test('queues and processes operations immediately', () async {
      await syncService.init();
      await syncService.queueOperation(
        collectionId: 'philosophy_books',
        operation: 'insert',
        data: {'title': 'Republic', 'author': 'Plato'},
      );

      expect(syncService.offlineQueue.isEmpty, isTrue);
    });
  });
}
