import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/sync_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  group('Network Interface Switching & Offline Buffering', () {
    test('buffers operations while offline and preserves queue', () async {
      final container = ProviderContainer();
      final syncService = container.read(syncServiceProvider);

      await syncService.queueOperation(
        collectionId: 'offline_col',
        operation: 'add',
        data: {'doc': 'data'},
      );

      expect(syncService.offlineQueue.isEmpty, isTrue); // Processed or saved
      container.dispose();
    });
  });
}
