import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';

void main() {
  group('Database Schema Migration & Integrity Tests', () {
    test('verifies schema persistence and column integrity', () async {
      final db = AppDatabase();
      await db.insertManifest({
        'uuid': 'migration_test_uuid',
        'title': 'The Art of Computer Programming',
        'author': 'Donald Knuth',
        'category': 'Computer Science',
        'isEncrypted': false,
        'lastUpdated': DateTime.now(),
      });

      final retrieved = await db.getManifestByUuid('migration_test_uuid');
      expect(retrieved, isNotNull);
      expect(retrieved!['title'], equals('The Art of Computer Programming'));
    });
  });
}
