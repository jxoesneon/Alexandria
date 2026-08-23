import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/services/sync_service.dart';

void main() {
  group('Wire Deserialization Security Fuzzing', () {
    test('rejects malformed QueuedOperation JSON payloads gracefully', () {
      final invalidJson = {'id': '1', 'collectionId': 'test'}; // Missing fields
      expect(() => QueuedOperation.fromJson(invalidJson), throwsA(anything));
    });
  });
}
