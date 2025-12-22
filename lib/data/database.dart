import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Content manifests - main content metadata
class ContentManifests extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().unique()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get author => text().nullable()();
  TextColumn get tags => text().nullable()(); // JSON array
  TextColumn get category => text().withDefault(const Constant('other'))();
  TextColumn get metadata => text().nullable()(); // JSON object
  BoolColumn get isEncrypted => boolean().withDefault(const Constant(false))();
  TextColumn get encryptionKey => text().nullable()();
  TextColumn get encryptionKeyHash => text().nullable()(); // SHA256 of key
  DateTimeColumn get lastUpdated => dateTime()();

  // Version chain fields (Spec §3.3)
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get parentCid => text().nullable()(); // Link to previous version
  TextColumn get siblingCids =>
      text().nullable()(); // JSON array of variant CIDs
  TextColumn get rootCid =>
      text().nullable()(); // Root of version tree (The Prism)

  // Publisher signature fields (Spec §3.2)
  TextColumn get publisherKey => text().nullable()(); // Ed25519 public key
  TextColumn get signature =>
      text().nullable()(); // Ed25519 signature of manifest
}

/// Content versions - individual versions with IPFS CIDs
class ContentVersions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cid => text().unique()();
  IntColumn get manifestId => integer().references(ContentManifests, #id)();
  TextColumn get language => text()();
  TextColumn get resolution => text().nullable()();
  TextColumn get format => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get createdData => dateTime()();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  IntColumn get peerCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastHealthCheck => dateTime().nullable()();
}

/// Honor validations - user votes and verifications
class HonorValidations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get validatorId => text()();
  TextColumn get targetCid => text()();
  IntColumn get score => integer()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get signature => text()();
}

/// User profiles - identity and reputation
class UserProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get publicKey => text().unique()();
  IntColumn get reputation => integer()();
  TextColumn get badges => text().nullable()(); // JSON array stored as string
  DateTimeColumn get lastActive => dateTime()();
}

@DriftDatabase(
  tables: [ContentManifests, ContentVersions, HonorValidations, UserProfiles],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(contentManifests, contentManifests.category);
          await m.addColumn(contentManifests, contentManifests.metadata);
        }
        if (from < 3) {
          // Add version chain fields (Spec §3.3)
          await m.addColumn(contentManifests, contentManifests.version);
          await m.addColumn(contentManifests, contentManifests.parentCid);
          await m.addColumn(contentManifests, contentManifests.siblingCids);
          await m.addColumn(contentManifests, contentManifests.rootCid);
          // Add publisher signature fields (Spec §3.2)
          await m.addColumn(contentManifests, contentManifests.publisherKey);
          await m.addColumn(contentManifests, contentManifests.signature);
          await m.addColumn(
            contentManifests,
            contentManifests.encryptionKeyHash,
          );
        }
      },
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'alexandria_db');
  }

  // --- ContentManifest Operations ---

  Future<int> insertManifest(ContentManifestsCompanion manifest) {
    return into(contentManifests).insert(manifest);
  }

  Future<ContentManifest?> getManifestByUuid(String uuid) {
    return (select(
      contentManifests,
    )..where((t) => t.uuid.equals(uuid))).getSingleOrNull();
  }

  Future<List<ContentManifest>> getAllManifests() {
    return (select(
      contentManifests,
    )..orderBy([(t) => OrderingTerm.desc(t.lastUpdated)])).get();
  }

  Future<List<ContentManifest>> getManifestsPaged({
    required int limit,
    required int offset,
  }) {
    return (select(contentManifests)
          ..orderBy([(t) => OrderingTerm.desc(t.lastUpdated)])
          ..limit(limit, offset: offset))
        .get();
  }

  Future<List<ContentManifest>> searchManifests(String query) {
    return (select(contentManifests)..where(
          (t) =>
              t.title.like('%$query%') |
              t.author.like('%$query%') |
              t.description.like('%$query%') |
              t.tags.like('%$query%'),
        ))
        .get();
  }

  Future<int> countManifests() async {
    final count = contentManifests.id.count();
    final query = selectOnly(contentManifests)..addColumns([count]);
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  Future<bool> updateManifest(ContentManifest manifest) {
    return update(contentManifests).replace(manifest);
  }

  // --- ContentVersion Operations ---

  Future<int> insertVersion(ContentVersionsCompanion version) {
    return into(contentVersions).insert(version);
  }

  Future<ContentVersion?> getVersionByCid(String cid) {
    return (select(
      contentVersions,
    )..where((t) => t.cid.equals(cid))).getSingleOrNull();
  }

  Future<List<ContentVersion>> getVersionsForManifest(int manifestId) {
    return (select(
      contentVersions,
    )..where((t) => t.manifestId.equals(manifestId))).get();
  }

  Future<List<ContentVersion>> getAllVersions() {
    return select(contentVersions).get();
  }

  Future<List<ContentVersion>> getEndangeredVersions(int threshold) {
    return (select(contentVersions)..where(
          (t) => t.peerCount.isSmallerThanValue(threshold) & t.isPinned.not(),
        ))
        .get();
  }

  Future<List<ContentVersion>> getPinnedVersions() {
    return (select(
      contentVersions,
    )..where((t) => t.isPinned.equals(true))).get();
  }

  Future<bool> updateVersion(ContentVersion version) {
    return update(contentVersions).replace(version);
  }

  // --- HonorValidation Operations ---

  Future<int> insertValidation(HonorValidationsCompanion validation) {
    return into(honorValidations).insert(validation);
  }

  Future<List<HonorValidation>> getValidationsForCid(String targetCid) {
    return (select(
      honorValidations,
    )..where((t) => t.targetCid.equals(targetCid))).get();
  }

  // --- UserProfile Operations ---

  Future<int> insertProfile(UserProfilesCompanion profile) {
    return into(userProfiles).insert(profile);
  }

  Future<UserProfile?> getProfileByPublicKey(String publicKey) {
    return (select(
      userProfiles,
    )..where((t) => t.publicKey.equals(publicKey))).getSingleOrNull();
  }

  Future<bool> updateProfile(UserProfile profile) {
    return update(userProfiles).replace(profile);
  }

  // --- Statistics Operations ---

  /// Returns a list of all dates where the user was active (created content or validated).
  /// Used for the Contribution Graph.
  Future<List<DateTime>> getUserActivityDates(String publicKey) async {
    // 1. Content Creations (Author)
    final contentQuery = select(contentManifests)
      ..where((t) => t.author.equals(publicKey));
    final contentDates = await contentQuery.map((row) => row.lastUpdated).get();

    // 2. Validations (Validator) - Assuming validatorId is the public key
    final validationQuery = select(honorValidations)
      ..where((t) => t.validatorId.equals(publicKey));
    final validationDates = await validationQuery
        .map((row) => row.timestamp)
        .get();

    return [...contentDates, ...validationDates];
  }
}
