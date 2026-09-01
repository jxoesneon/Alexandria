import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'database.g.dart';

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
  TextColumn get tags => text().nullable()();
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

@DriftDatabase(
    tables: [ContentManifests, ContentVersions, UserProfiles, HonorValidations])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  Future<void> insertManifest(Map<String, dynamic> data) async {
    await into(contentManifests).insert(
      ContentManifestsCompanion.insert(
        uuid: data['uuid'] as String,
        title: data['title'] as String,
        lastUpdated: (data['lastUpdated'] as DateTime?) ?? DateTime.now(),
        author: Value(data['author'] as String?),
        description: Value(data['description'] as String?),
        category: Value(data['category'] as String? ?? 'other'),
        tags: Value(data['tags'] as String?),
        metadata: Value(data['metadata'] as String?),
        isEncrypted: Value(data['isEncrypted'] as bool? ?? false),
        encryptionKey: Value(data['encryptionKey'] as String?),
      ),
    );
  }

  Future<Map<String, dynamic>?> getManifestByUuid(String uuid) async {
    final query = select(contentManifests)..where((m) => m.uuid.equals(uuid));
    final row = await query.getSingleOrNull();
    return row == null ? null : _manifestToMap(row);
  }

  Future<List<ContentManifest>> getAllManifests() async {
    return select(contentManifests).get();
  }

  Future<void> insertVersion(Map<String, dynamic> data) async {
    await into(contentVersions).insert(
      ContentVersionsCompanion.insert(
        manifestId: data['manifestId'] as int,
        cid: data['cid'] as String,
        sizeBytes: data['sizeBytes'] as int? ?? 0,
        createdData: (data['createdData'] as DateTime?) ?? DateTime.now(),
        language: Value(data['language'] as String? ?? 'en'),
        format: Value(data['format'] as String? ?? 'bin'),
        peerCount: Value(data['peerCount'] as int? ?? 0),
        isPinned: Value(data['isPinned'] as bool? ?? true),
        lastHealthCheck: Value(data['lastHealthCheck'] as DateTime?),
      ),
    );
  }

  Future<Map<String, dynamic>?> getVersionByCid(String cid) async {
    final query = select(contentVersions)..where((v) => v.cid.equals(cid));
    final row = await query.getSingleOrNull();
    return row == null ? null : _versionToMap(row);
  }

  Future<List<ContentVersion>> getEndangeredVersions(int threshold) async {
    final query = select(contentVersions)
      ..where((v) => v.peerCount.isSmallerThanValue(threshold));
    return query.get();
  }

  Future<List<ContentVersion>> getVersionsForManifest(int manifestId) async {
    final query = select(contentVersions)
      ..where((v) => v.manifestId.equals(manifestId));
    return query.get();
  }

  Future<List<DateTime>> getUserActivityDates(String publicKey) async {
    return [];
  }

  Future<UserProfile?> getProfileByPublicKey(String publicKey) async {
    final query = select(userProfiles)
      ..where((p) => p.publicKey.equals(publicKey));
    return query.getSingleOrNull();
  }

  static Map<String, dynamic> _manifestToMap(ContentManifest m) => {
        'id': m.id,
        'uuid': m.uuid,
        'title': m.title,
        'author': m.author,
        'description': m.description,
        'category': m.category,
        'tags': m.tags,
        'metadata': m.metadata,
        'isEncrypted': m.isEncrypted,
        'encryptionKey': m.encryptionKey,
        'lastUpdated': m.lastUpdated,
      };

  static Map<String, dynamic> _versionToMap(ContentVersion v) => {
        'id': v.id,
        'manifestId': v.manifestId,
        'cid': v.cid,
        'language': v.language,
        'format': v.format,
        'sizeBytes': v.sizeBytes,
        'peerCount': v.peerCount,
        'isPinned': v.isPinned,
        'lastHealthCheck': v.lastHealthCheck,
        'createdData': v.createdData,
      };
}
