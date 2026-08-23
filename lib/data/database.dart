import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

class ContentManifests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get category => text().withDefault(const Constant('other'))();
  TextColumn get metadata => text().nullable()();
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();
  TextColumn get encryptionKey => text().nullable()();
  DateTimeColumn get lastUpdated => dateTime()();
}

class ContentVersions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get manifestId => integer().references(ContentManifests, #id)();
  TextColumn get cid => text().unique()();
  TextColumn get language => text().withDefault(const Constant('en'))();
  TextColumn get format => text().withDefault(const Constant('bin'))();
  IntColumn get sizeBytes => integer()();
  IntColumn get peerCount => integer().withDefault(const Constant(0))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastHealthCheck => dateTime().nullable()();
  DateTimeColumn get createdData => dateTime()();
}

class UserProfiles extends Table {
  TextColumn get publicKey => text()();
  IntColumn get reputation => integer().withDefault(const Constant(10))();
  DateTimeColumn get lastActive => dateTime()();

  @override
  Set<Column> get primaryKey => {publicKey};
}

class HonorValidations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get validatorId => text()();
  TextColumn get targetCid => text()();
  IntColumn get score => integer()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get signature => text()();
}

class AppDatabase {
  final Map<String, Map<String, dynamic>> _manifests = {};
  final Map<String, Map<String, dynamic>> _versions = {};
  final Map<String, int> _profiles = {};
  final List<Map<String, dynamic>> _validations = {};

  Future<void> close() async {}

  Future<void> insertManifest(Map<String, dynamic> data) async {
    _manifests[data['uuid'] as String] = data;
  }

  Future<Map<String, dynamic>?> getManifestByUuid(String uuid) async {
    return _manifests[uuid];
  }

  Future<List<Map<String, dynamic>>> getAllManifests() async {
    return _manifests.values.toList();
  }

  Future<void> insertVersion(Map<String, dynamic> data) async {
    _versions[data['cid'] as String] = data;
  }

  Future<Map<String, dynamic>?> getVersionByCid(String cid) async {
    return _versions[cid];
  }

  Future<List<Map<String, dynamic>>> getEndangeredVersions(int threshold) async {
    return _versions.values.where((v) => (v['peerCount'] as int? ?? 0) < threshold).toList();
  }
}
