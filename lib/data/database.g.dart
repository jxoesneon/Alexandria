// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ContentManifestsTable extends ContentManifests
    with TableInfo<$ContentManifestsTable, ContentManifest> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContentManifestsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
      'uuid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('other'));
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
      'tags', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _metadataMeta =
      const VerificationMeta('metadata');
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
      'metadata', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isEncryptedMeta =
      const VerificationMeta('isEncrypted');
  @override
  late final GeneratedColumn<bool> isEncrypted = GeneratedColumn<bool>(
      'is_encrypted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_encrypted" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _encryptionKeyMeta =
      const VerificationMeta('encryptionKey');
  @override
  late final GeneratedColumn<String> encryptionKey = GeneratedColumn<String>(
      'encryption_key', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastUpdatedMeta =
      const VerificationMeta('lastUpdated');
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
      'last_updated', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        uuid,
        title,
        author,
        description,
        category,
        tags,
        metadata,
        isEncrypted,
        encryptionKey,
        lastUpdated
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_manifests';
  @override
  VerificationContext validateIntegrity(Insertable<ContentManifest> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
          _uuidMeta, uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta));
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    }
    if (data.containsKey('tags')) {
      context.handle(
          _tagsMeta, tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta));
    }
    if (data.containsKey('metadata')) {
      context.handle(_metadataMeta,
          metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta));
    }
    if (data.containsKey('is_encrypted')) {
      context.handle(
          _isEncryptedMeta,
          isEncrypted.isAcceptableOrUnknown(
              data['is_encrypted']!, _isEncryptedMeta));
    }
    if (data.containsKey('encryption_key')) {
      context.handle(
          _encryptionKeyMeta,
          encryptionKey.isAcceptableOrUnknown(
              data['encryption_key']!, _encryptionKeyMeta));
    }
    if (data.containsKey('last_updated')) {
      context.handle(
          _lastUpdatedMeta,
          lastUpdated.isAcceptableOrUnknown(
              data['last_updated']!, _lastUpdatedMeta));
    } else if (isInserting) {
      context.missing(_lastUpdatedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContentManifest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentManifest(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      uuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}uuid'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author']),
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      tags: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tags']),
      metadata: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}metadata']),
      isEncrypted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_encrypted'])!,
      encryptionKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}encryption_key']),
      lastUpdated: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_updated'])!,
    );
  }

  @override
  $ContentManifestsTable createAlias(String alias) {
    return $ContentManifestsTable(attachedDatabase, alias);
  }
}

class ContentManifest extends DataClass implements Insertable<ContentManifest> {
  final int id;
  final String uuid;
  final String title;
  final String? author;
  final String? description;
  final String category;
  final String? tags;
  final String? metadata;
  final bool isEncrypted;
  final String? encryptionKey;
  final DateTime lastUpdated;
  const ContentManifest(
      {required this.id,
      required this.uuid,
      required this.title,
      this.author,
      this.description,
      required this.category,
      this.tags,
      this.metadata,
      required this.isEncrypted,
      this.encryptionKey,
      required this.lastUpdated});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || tags != null) {
      map['tags'] = Variable<String>(tags);
    }
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    map['is_encrypted'] = Variable<bool>(isEncrypted);
    if (!nullToAbsent || encryptionKey != null) {
      map['encryption_key'] = Variable<String>(encryptionKey);
    }
    map['last_updated'] = Variable<DateTime>(lastUpdated);
    return map;
  }

  ContentManifestsCompanion toCompanion(bool nullToAbsent) {
    return ContentManifestsCompanion(
      id: Value(id),
      uuid: Value(uuid),
      title: Value(title),
      author:
          author == null && nullToAbsent ? const Value.absent() : Value(author),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      category: Value(category),
      tags: tags == null && nullToAbsent ? const Value.absent() : Value(tags),
      metadata: metadata == null && nullToAbsent
          ? const Value.absent()
          : Value(metadata),
      isEncrypted: Value(isEncrypted),
      encryptionKey: encryptionKey == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptionKey),
      lastUpdated: Value(lastUpdated),
    );
  }

  factory ContentManifest.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentManifest(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      description: serializer.fromJson<String?>(json['description']),
      category: serializer.fromJson<String>(json['category']),
      tags: serializer.fromJson<String?>(json['tags']),
      metadata: serializer.fromJson<String?>(json['metadata']),
      isEncrypted: serializer.fromJson<bool>(json['isEncrypted']),
      encryptionKey: serializer.fromJson<String?>(json['encryptionKey']),
      lastUpdated: serializer.fromJson<DateTime>(json['lastUpdated']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'description': serializer.toJson<String?>(description),
      'category': serializer.toJson<String>(category),
      'tags': serializer.toJson<String?>(tags),
      'metadata': serializer.toJson<String?>(metadata),
      'isEncrypted': serializer.toJson<bool>(isEncrypted),
      'encryptionKey': serializer.toJson<String?>(encryptionKey),
      'lastUpdated': serializer.toJson<DateTime>(lastUpdated),
    };
  }

  ContentManifest copyWith(
          {int? id,
          String? uuid,
          String? title,
          Value<String?> author = const Value.absent(),
          Value<String?> description = const Value.absent(),
          String? category,
          Value<String?> tags = const Value.absent(),
          Value<String?> metadata = const Value.absent(),
          bool? isEncrypted,
          Value<String?> encryptionKey = const Value.absent(),
          DateTime? lastUpdated}) =>
      ContentManifest(
        id: id ?? this.id,
        uuid: uuid ?? this.uuid,
        title: title ?? this.title,
        author: author.present ? author.value : this.author,
        description: description.present ? description.value : this.description,
        category: category ?? this.category,
        tags: tags.present ? tags.value : this.tags,
        metadata: metadata.present ? metadata.value : this.metadata,
        isEncrypted: isEncrypted ?? this.isEncrypted,
        encryptionKey:
            encryptionKey.present ? encryptionKey.value : this.encryptionKey,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
  ContentManifest copyWithCompanion(ContentManifestsCompanion data) {
    return ContentManifest(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      description:
          data.description.present ? data.description.value : this.description,
      category: data.category.present ? data.category.value : this.category,
      tags: data.tags.present ? data.tags.value : this.tags,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      isEncrypted:
          data.isEncrypted.present ? data.isEncrypted.value : this.isEncrypted,
      encryptionKey: data.encryptionKey.present
          ? data.encryptionKey.value
          : this.encryptionKey,
      lastUpdated:
          data.lastUpdated.present ? data.lastUpdated.value : this.lastUpdated,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentManifest(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('tags: $tags, ')
          ..write('metadata: $metadata, ')
          ..write('isEncrypted: $isEncrypted, ')
          ..write('encryptionKey: $encryptionKey, ')
          ..write('lastUpdated: $lastUpdated')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, uuid, title, author, description,
      category, tags, metadata, isEncrypted, encryptionKey, lastUpdated);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentManifest &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.title == this.title &&
          other.author == this.author &&
          other.description == this.description &&
          other.category == this.category &&
          other.tags == this.tags &&
          other.metadata == this.metadata &&
          other.isEncrypted == this.isEncrypted &&
          other.encryptionKey == this.encryptionKey &&
          other.lastUpdated == this.lastUpdated);
}

class ContentManifestsCompanion extends UpdateCompanion<ContentManifest> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> title;
  final Value<String?> author;
  final Value<String?> description;
  final Value<String> category;
  final Value<String?> tags;
  final Value<String?> metadata;
  final Value<bool> isEncrypted;
  final Value<String?> encryptionKey;
  final Value<DateTime> lastUpdated;
  const ContentManifestsCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.tags = const Value.absent(),
    this.metadata = const Value.absent(),
    this.isEncrypted = const Value.absent(),
    this.encryptionKey = const Value.absent(),
    this.lastUpdated = const Value.absent(),
  });
  ContentManifestsCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String title,
    this.author = const Value.absent(),
    this.description = const Value.absent(),
    this.category = const Value.absent(),
    this.tags = const Value.absent(),
    this.metadata = const Value.absent(),
    this.isEncrypted = const Value.absent(),
    this.encryptionKey = const Value.absent(),
    required DateTime lastUpdated,
  })  : uuid = Value(uuid),
        title = Value(title),
        lastUpdated = Value(lastUpdated);
  static Insertable<ContentManifest> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? description,
    Expression<String>? category,
    Expression<String>? tags,
    Expression<String>? metadata,
    Expression<bool>? isEncrypted,
    Expression<String>? encryptionKey,
    Expression<DateTime>? lastUpdated,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (description != null) 'description': description,
      if (category != null) 'category': category,
      if (tags != null) 'tags': tags,
      if (metadata != null) 'metadata': metadata,
      if (isEncrypted != null) 'is_encrypted': isEncrypted,
      if (encryptionKey != null) 'encryption_key': encryptionKey,
      if (lastUpdated != null) 'last_updated': lastUpdated,
    });
  }

  ContentManifestsCompanion copyWith(
      {Value<int>? id,
      Value<String>? uuid,
      Value<String>? title,
      Value<String?>? author,
      Value<String?>? description,
      Value<String>? category,
      Value<String?>? tags,
      Value<String?>? metadata,
      Value<bool>? isEncrypted,
      Value<String?>? encryptionKey,
      Value<DateTime>? lastUpdated}) {
    return ContentManifestsCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      metadata: metadata ?? this.metadata,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (uuid.present) {
      map['uuid'] = Variable<String>(uuid.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (metadata.present) {
      map['metadata'] = Variable<String>(metadata.value);
    }
    if (isEncrypted.present) {
      map['is_encrypted'] = Variable<bool>(isEncrypted.value);
    }
    if (encryptionKey.present) {
      map['encryption_key'] = Variable<String>(encryptionKey.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentManifestsCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('description: $description, ')
          ..write('category: $category, ')
          ..write('tags: $tags, ')
          ..write('metadata: $metadata, ')
          ..write('isEncrypted: $isEncrypted, ')
          ..write('encryptionKey: $encryptionKey, ')
          ..write('lastUpdated: $lastUpdated')
          ..write(')'))
        .toString();
  }
}

class $ContentVersionsTable extends ContentVersions
    with TableInfo<$ContentVersionsTable, ContentVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ContentVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _manifestIdMeta =
      const VerificationMeta('manifestId');
  @override
  late final GeneratedColumn<int> manifestId = GeneratedColumn<int>(
      'manifest_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES content_manifests (id)'));
  static const VerificationMeta _cidMeta = const VerificationMeta('cid');
  @override
  late final GeneratedColumn<String> cid = GeneratedColumn<String>(
      'cid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _languageMeta =
      const VerificationMeta('language');
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
      'language', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('en'));
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
      'format', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('bin'));
  static const VerificationMeta _sizeBytesMeta =
      const VerificationMeta('sizeBytes');
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
      'size_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _peerCountMeta =
      const VerificationMeta('peerCount');
  @override
  late final GeneratedColumn<int> peerCount = GeneratedColumn<int>(
      'peer_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isPinnedMeta =
      const VerificationMeta('isPinned');
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
      'is_pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_pinned" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _lastHealthCheckMeta =
      const VerificationMeta('lastHealthCheck');
  @override
  late final GeneratedColumn<DateTime> lastHealthCheck =
      GeneratedColumn<DateTime>('last_health_check', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdDataMeta =
      const VerificationMeta('createdData');
  @override
  late final GeneratedColumn<DateTime> createdData = GeneratedColumn<DateTime>(
      'created_data', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        manifestId,
        cid,
        language,
        format,
        sizeBytes,
        peerCount,
        isPinned,
        lastHealthCheck,
        createdData
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_versions';
  @override
  VerificationContext validateIntegrity(Insertable<ContentVersion> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('manifest_id')) {
      context.handle(
          _manifestIdMeta,
          manifestId.isAcceptableOrUnknown(
              data['manifest_id']!, _manifestIdMeta));
    } else if (isInserting) {
      context.missing(_manifestIdMeta);
    }
    if (data.containsKey('cid')) {
      context.handle(
          _cidMeta, cid.isAcceptableOrUnknown(data['cid']!, _cidMeta));
    } else if (isInserting) {
      context.missing(_cidMeta);
    }
    if (data.containsKey('language')) {
      context.handle(_languageMeta,
          language.isAcceptableOrUnknown(data['language']!, _languageMeta));
    }
    if (data.containsKey('format')) {
      context.handle(_formatMeta,
          format.isAcceptableOrUnknown(data['format']!, _formatMeta));
    }
    if (data.containsKey('size_bytes')) {
      context.handle(_sizeBytesMeta,
          sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta));
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('peer_count')) {
      context.handle(_peerCountMeta,
          peerCount.isAcceptableOrUnknown(data['peer_count']!, _peerCountMeta));
    }
    if (data.containsKey('is_pinned')) {
      context.handle(_isPinnedMeta,
          isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta));
    }
    if (data.containsKey('last_health_check')) {
      context.handle(
          _lastHealthCheckMeta,
          lastHealthCheck.isAcceptableOrUnknown(
              data['last_health_check']!, _lastHealthCheckMeta));
    }
    if (data.containsKey('created_data')) {
      context.handle(
          _createdDataMeta,
          createdData.isAcceptableOrUnknown(
              data['created_data']!, _createdDataMeta));
    } else if (isInserting) {
      context.missing(_createdDataMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContentVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentVersion(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      manifestId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}manifest_id'])!,
      cid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cid'])!,
      language: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}language'])!,
      format: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}format'])!,
      sizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size_bytes'])!,
      peerCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}peer_count'])!,
      isPinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_pinned'])!,
      lastHealthCheck: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_health_check']),
      createdData: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_data'])!,
    );
  }

  @override
  $ContentVersionsTable createAlias(String alias) {
    return $ContentVersionsTable(attachedDatabase, alias);
  }
}

class ContentVersion extends DataClass implements Insertable<ContentVersion> {
  final int id;
  final int manifestId;
  final String cid;
  final String language;
  final String format;
  final int sizeBytes;
  final int peerCount;
  final bool isPinned;
  final DateTime? lastHealthCheck;
  final DateTime createdData;
  const ContentVersion(
      {required this.id,
      required this.manifestId,
      required this.cid,
      required this.language,
      required this.format,
      required this.sizeBytes,
      required this.peerCount,
      required this.isPinned,
      this.lastHealthCheck,
      required this.createdData});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['manifest_id'] = Variable<int>(manifestId);
    map['cid'] = Variable<String>(cid);
    map['language'] = Variable<String>(language);
    map['format'] = Variable<String>(format);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['peer_count'] = Variable<int>(peerCount);
    map['is_pinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || lastHealthCheck != null) {
      map['last_health_check'] = Variable<DateTime>(lastHealthCheck);
    }
    map['created_data'] = Variable<DateTime>(createdData);
    return map;
  }

  ContentVersionsCompanion toCompanion(bool nullToAbsent) {
    return ContentVersionsCompanion(
      id: Value(id),
      manifestId: Value(manifestId),
      cid: Value(cid),
      language: Value(language),
      format: Value(format),
      sizeBytes: Value(sizeBytes),
      peerCount: Value(peerCount),
      isPinned: Value(isPinned),
      lastHealthCheck: lastHealthCheck == null && nullToAbsent
          ? const Value.absent()
          : Value(lastHealthCheck),
      createdData: Value(createdData),
    );
  }

  factory ContentVersion.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentVersion(
      id: serializer.fromJson<int>(json['id']),
      manifestId: serializer.fromJson<int>(json['manifestId']),
      cid: serializer.fromJson<String>(json['cid']),
      language: serializer.fromJson<String>(json['language']),
      format: serializer.fromJson<String>(json['format']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      peerCount: serializer.fromJson<int>(json['peerCount']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      lastHealthCheck: serializer.fromJson<DateTime?>(json['lastHealthCheck']),
      createdData: serializer.fromJson<DateTime>(json['createdData']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'manifestId': serializer.toJson<int>(manifestId),
      'cid': serializer.toJson<String>(cid),
      'language': serializer.toJson<String>(language),
      'format': serializer.toJson<String>(format),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'peerCount': serializer.toJson<int>(peerCount),
      'isPinned': serializer.toJson<bool>(isPinned),
      'lastHealthCheck': serializer.toJson<DateTime?>(lastHealthCheck),
      'createdData': serializer.toJson<DateTime>(createdData),
    };
  }

  ContentVersion copyWith(
          {int? id,
          int? manifestId,
          String? cid,
          String? language,
          String? format,
          int? sizeBytes,
          int? peerCount,
          bool? isPinned,
          Value<DateTime?> lastHealthCheck = const Value.absent(),
          DateTime? createdData}) =>
      ContentVersion(
        id: id ?? this.id,
        manifestId: manifestId ?? this.manifestId,
        cid: cid ?? this.cid,
        language: language ?? this.language,
        format: format ?? this.format,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        peerCount: peerCount ?? this.peerCount,
        isPinned: isPinned ?? this.isPinned,
        lastHealthCheck: lastHealthCheck.present
            ? lastHealthCheck.value
            : this.lastHealthCheck,
        createdData: createdData ?? this.createdData,
      );
  ContentVersion copyWithCompanion(ContentVersionsCompanion data) {
    return ContentVersion(
      id: data.id.present ? data.id.value : this.id,
      manifestId:
          data.manifestId.present ? data.manifestId.value : this.manifestId,
      cid: data.cid.present ? data.cid.value : this.cid,
      language: data.language.present ? data.language.value : this.language,
      format: data.format.present ? data.format.value : this.format,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      peerCount: data.peerCount.present ? data.peerCount.value : this.peerCount,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      lastHealthCheck: data.lastHealthCheck.present
          ? data.lastHealthCheck.value
          : this.lastHealthCheck,
      createdData:
          data.createdData.present ? data.createdData.value : this.createdData,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentVersion(')
          ..write('id: $id, ')
          ..write('manifestId: $manifestId, ')
          ..write('cid: $cid, ')
          ..write('language: $language, ')
          ..write('format: $format, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('peerCount: $peerCount, ')
          ..write('isPinned: $isPinned, ')
          ..write('lastHealthCheck: $lastHealthCheck, ')
          ..write('createdData: $createdData')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, manifestId, cid, language, format,
      sizeBytes, peerCount, isPinned, lastHealthCheck, createdData);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentVersion &&
          other.id == this.id &&
          other.manifestId == this.manifestId &&
          other.cid == this.cid &&
          other.language == this.language &&
          other.format == this.format &&
          other.sizeBytes == this.sizeBytes &&
          other.peerCount == this.peerCount &&
          other.isPinned == this.isPinned &&
          other.lastHealthCheck == this.lastHealthCheck &&
          other.createdData == this.createdData);
}

class ContentVersionsCompanion extends UpdateCompanion<ContentVersion> {
  final Value<int> id;
  final Value<int> manifestId;
  final Value<String> cid;
  final Value<String> language;
  final Value<String> format;
  final Value<int> sizeBytes;
  final Value<int> peerCount;
  final Value<bool> isPinned;
  final Value<DateTime?> lastHealthCheck;
  final Value<DateTime> createdData;
  const ContentVersionsCompanion({
    this.id = const Value.absent(),
    this.manifestId = const Value.absent(),
    this.cid = const Value.absent(),
    this.language = const Value.absent(),
    this.format = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.peerCount = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.lastHealthCheck = const Value.absent(),
    this.createdData = const Value.absent(),
  });
  ContentVersionsCompanion.insert({
    this.id = const Value.absent(),
    required int manifestId,
    required String cid,
    this.language = const Value.absent(),
    this.format = const Value.absent(),
    required int sizeBytes,
    this.peerCount = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.lastHealthCheck = const Value.absent(),
    required DateTime createdData,
  })  : manifestId = Value(manifestId),
        cid = Value(cid),
        sizeBytes = Value(sizeBytes),
        createdData = Value(createdData);
  static Insertable<ContentVersion> custom({
    Expression<int>? id,
    Expression<int>? manifestId,
    Expression<String>? cid,
    Expression<String>? language,
    Expression<String>? format,
    Expression<int>? sizeBytes,
    Expression<int>? peerCount,
    Expression<bool>? isPinned,
    Expression<DateTime>? lastHealthCheck,
    Expression<DateTime>? createdData,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (manifestId != null) 'manifest_id': manifestId,
      if (cid != null) 'cid': cid,
      if (language != null) 'language': language,
      if (format != null) 'format': format,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (peerCount != null) 'peer_count': peerCount,
      if (isPinned != null) 'is_pinned': isPinned,
      if (lastHealthCheck != null) 'last_health_check': lastHealthCheck,
      if (createdData != null) 'created_data': createdData,
    });
  }

  ContentVersionsCompanion copyWith(
      {Value<int>? id,
      Value<int>? manifestId,
      Value<String>? cid,
      Value<String>? language,
      Value<String>? format,
      Value<int>? sizeBytes,
      Value<int>? peerCount,
      Value<bool>? isPinned,
      Value<DateTime?>? lastHealthCheck,
      Value<DateTime>? createdData}) {
    return ContentVersionsCompanion(
      id: id ?? this.id,
      manifestId: manifestId ?? this.manifestId,
      cid: cid ?? this.cid,
      language: language ?? this.language,
      format: format ?? this.format,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      peerCount: peerCount ?? this.peerCount,
      isPinned: isPinned ?? this.isPinned,
      lastHealthCheck: lastHealthCheck ?? this.lastHealthCheck,
      createdData: createdData ?? this.createdData,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (manifestId.present) {
      map['manifest_id'] = Variable<int>(manifestId.value);
    }
    if (cid.present) {
      map['cid'] = Variable<String>(cid.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (peerCount.present) {
      map['peer_count'] = Variable<int>(peerCount.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (lastHealthCheck.present) {
      map['last_health_check'] = Variable<DateTime>(lastHealthCheck.value);
    }
    if (createdData.present) {
      map['created_data'] = Variable<DateTime>(createdData.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentVersionsCompanion(')
          ..write('id: $id, ')
          ..write('manifestId: $manifestId, ')
          ..write('cid: $cid, ')
          ..write('language: $language, ')
          ..write('format: $format, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('peerCount: $peerCount, ')
          ..write('isPinned: $isPinned, ')
          ..write('lastHealthCheck: $lastHealthCheck, ')
          ..write('createdData: $createdData')
          ..write(')'))
        .toString();
  }
}

class $UserProfilesTable extends UserProfiles
    with TableInfo<$UserProfilesTable, UserProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _publicKeyMeta =
      const VerificationMeta('publicKey');
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
      'public_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _reputationMeta =
      const VerificationMeta('reputation');
  @override
  late final GeneratedColumn<int> reputation = GeneratedColumn<int>(
      'reputation', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(10));
  static const VerificationMeta _lastActiveMeta =
      const VerificationMeta('lastActive');
  @override
  late final GeneratedColumn<DateTime> lastActive = GeneratedColumn<DateTime>(
      'last_active', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [publicKey, reputation, lastActive];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_profiles';
  @override
  VerificationContext validateIntegrity(Insertable<UserProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('public_key')) {
      context.handle(_publicKeyMeta,
          publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta));
    } else if (isInserting) {
      context.missing(_publicKeyMeta);
    }
    if (data.containsKey('reputation')) {
      context.handle(
          _reputationMeta,
          reputation.isAcceptableOrUnknown(
              data['reputation']!, _reputationMeta));
    }
    if (data.containsKey('last_active')) {
      context.handle(
          _lastActiveMeta,
          lastActive.isAcceptableOrUnknown(
              data['last_active']!, _lastActiveMeta));
    } else if (isInserting) {
      context.missing(_lastActiveMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {publicKey};
  @override
  UserProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserProfile(
      publicKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}public_key'])!,
      reputation: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reputation'])!,
      lastActive: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_active'])!,
    );
  }

  @override
  $UserProfilesTable createAlias(String alias) {
    return $UserProfilesTable(attachedDatabase, alias);
  }
}

class UserProfile extends DataClass implements Insertable<UserProfile> {
  final String publicKey;
  final int reputation;
  final DateTime lastActive;
  const UserProfile(
      {required this.publicKey,
      required this.reputation,
      required this.lastActive});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['public_key'] = Variable<String>(publicKey);
    map['reputation'] = Variable<int>(reputation);
    map['last_active'] = Variable<DateTime>(lastActive);
    return map;
  }

  UserProfilesCompanion toCompanion(bool nullToAbsent) {
    return UserProfilesCompanion(
      publicKey: Value(publicKey),
      reputation: Value(reputation),
      lastActive: Value(lastActive),
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserProfile(
      publicKey: serializer.fromJson<String>(json['publicKey']),
      reputation: serializer.fromJson<int>(json['reputation']),
      lastActive: serializer.fromJson<DateTime>(json['lastActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'publicKey': serializer.toJson<String>(publicKey),
      'reputation': serializer.toJson<int>(reputation),
      'lastActive': serializer.toJson<DateTime>(lastActive),
    };
  }

  UserProfile copyWith(
          {String? publicKey, int? reputation, DateTime? lastActive}) =>
      UserProfile(
        publicKey: publicKey ?? this.publicKey,
        reputation: reputation ?? this.reputation,
        lastActive: lastActive ?? this.lastActive,
      );
  UserProfile copyWithCompanion(UserProfilesCompanion data) {
    return UserProfile(
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      reputation:
          data.reputation.present ? data.reputation.value : this.reputation,
      lastActive:
          data.lastActive.present ? data.lastActive.value : this.lastActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserProfile(')
          ..write('publicKey: $publicKey, ')
          ..write('reputation: $reputation, ')
          ..write('lastActive: $lastActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(publicKey, reputation, lastActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserProfile &&
          other.publicKey == this.publicKey &&
          other.reputation == this.reputation &&
          other.lastActive == this.lastActive);
}

class UserProfilesCompanion extends UpdateCompanion<UserProfile> {
  final Value<String> publicKey;
  final Value<int> reputation;
  final Value<DateTime> lastActive;
  final Value<int> rowid;
  const UserProfilesCompanion({
    this.publicKey = const Value.absent(),
    this.reputation = const Value.absent(),
    this.lastActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserProfilesCompanion.insert({
    required String publicKey,
    this.reputation = const Value.absent(),
    required DateTime lastActive,
    this.rowid = const Value.absent(),
  })  : publicKey = Value(publicKey),
        lastActive = Value(lastActive);
  static Insertable<UserProfile> custom({
    Expression<String>? publicKey,
    Expression<int>? reputation,
    Expression<DateTime>? lastActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (publicKey != null) 'public_key': publicKey,
      if (reputation != null) 'reputation': reputation,
      if (lastActive != null) 'last_active': lastActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserProfilesCompanion copyWith(
      {Value<String>? publicKey,
      Value<int>? reputation,
      Value<DateTime>? lastActive,
      Value<int>? rowid}) {
    return UserProfilesCompanion(
      publicKey: publicKey ?? this.publicKey,
      reputation: reputation ?? this.reputation,
      lastActive: lastActive ?? this.lastActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (reputation.present) {
      map['reputation'] = Variable<int>(reputation.value);
    }
    if (lastActive.present) {
      map['last_active'] = Variable<DateTime>(lastActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserProfilesCompanion(')
          ..write('publicKey: $publicKey, ')
          ..write('reputation: $reputation, ')
          ..write('lastActive: $lastActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HonorValidationsTable extends HonorValidations
    with TableInfo<$HonorValidationsTable, HonorValidation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HonorValidationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _validatorIdMeta =
      const VerificationMeta('validatorId');
  @override
  late final GeneratedColumn<String> validatorId = GeneratedColumn<String>(
      'validator_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _targetCidMeta =
      const VerificationMeta('targetCid');
  @override
  late final GeneratedColumn<String> targetCid = GeneratedColumn<String>(
      'target_cid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
      'score', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _signatureMeta =
      const VerificationMeta('signature');
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
      'signature', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, validatorId, targetCid, score, timestamp, signature];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'honor_validations';
  @override
  VerificationContext validateIntegrity(Insertable<HonorValidation> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('validator_id')) {
      context.handle(
          _validatorIdMeta,
          validatorId.isAcceptableOrUnknown(
              data['validator_id']!, _validatorIdMeta));
    } else if (isInserting) {
      context.missing(_validatorIdMeta);
    }
    if (data.containsKey('target_cid')) {
      context.handle(_targetCidMeta,
          targetCid.isAcceptableOrUnknown(data['target_cid']!, _targetCidMeta));
    } else if (isInserting) {
      context.missing(_targetCidMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
          _scoreMeta, score.isAcceptableOrUnknown(data['score']!, _scoreMeta));
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('signature')) {
      context.handle(_signatureMeta,
          signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta));
    } else if (isInserting) {
      context.missing(_signatureMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HonorValidation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HonorValidation(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      validatorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}validator_id'])!,
      targetCid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}target_cid'])!,
      score: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}score'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
      signature: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}signature'])!,
    );
  }

  @override
  $HonorValidationsTable createAlias(String alias) {
    return $HonorValidationsTable(attachedDatabase, alias);
  }
}

class HonorValidation extends DataClass implements Insertable<HonorValidation> {
  final int id;
  final String validatorId;
  final String targetCid;
  final int score;
  final DateTime timestamp;
  final String signature;
  const HonorValidation(
      {required this.id,
      required this.validatorId,
      required this.targetCid,
      required this.score,
      required this.timestamp,
      required this.signature});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['validator_id'] = Variable<String>(validatorId);
    map['target_cid'] = Variable<String>(targetCid);
    map['score'] = Variable<int>(score);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['signature'] = Variable<String>(signature);
    return map;
  }

  HonorValidationsCompanion toCompanion(bool nullToAbsent) {
    return HonorValidationsCompanion(
      id: Value(id),
      validatorId: Value(validatorId),
      targetCid: Value(targetCid),
      score: Value(score),
      timestamp: Value(timestamp),
      signature: Value(signature),
    );
  }

  factory HonorValidation.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HonorValidation(
      id: serializer.fromJson<int>(json['id']),
      validatorId: serializer.fromJson<String>(json['validatorId']),
      targetCid: serializer.fromJson<String>(json['targetCid']),
      score: serializer.fromJson<int>(json['score']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      signature: serializer.fromJson<String>(json['signature']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'validatorId': serializer.toJson<String>(validatorId),
      'targetCid': serializer.toJson<String>(targetCid),
      'score': serializer.toJson<int>(score),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'signature': serializer.toJson<String>(signature),
    };
  }

  HonorValidation copyWith(
          {int? id,
          String? validatorId,
          String? targetCid,
          int? score,
          DateTime? timestamp,
          String? signature}) =>
      HonorValidation(
        id: id ?? this.id,
        validatorId: validatorId ?? this.validatorId,
        targetCid: targetCid ?? this.targetCid,
        score: score ?? this.score,
        timestamp: timestamp ?? this.timestamp,
        signature: signature ?? this.signature,
      );
  HonorValidation copyWithCompanion(HonorValidationsCompanion data) {
    return HonorValidation(
      id: data.id.present ? data.id.value : this.id,
      validatorId:
          data.validatorId.present ? data.validatorId.value : this.validatorId,
      targetCid: data.targetCid.present ? data.targetCid.value : this.targetCid,
      score: data.score.present ? data.score.value : this.score,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      signature: data.signature.present ? data.signature.value : this.signature,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HonorValidation(')
          ..write('id: $id, ')
          ..write('validatorId: $validatorId, ')
          ..write('targetCid: $targetCid, ')
          ..write('score: $score, ')
          ..write('timestamp: $timestamp, ')
          ..write('signature: $signature')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, validatorId, targetCid, score, timestamp, signature);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HonorValidation &&
          other.id == this.id &&
          other.validatorId == this.validatorId &&
          other.targetCid == this.targetCid &&
          other.score == this.score &&
          other.timestamp == this.timestamp &&
          other.signature == this.signature);
}

class HonorValidationsCompanion extends UpdateCompanion<HonorValidation> {
  final Value<int> id;
  final Value<String> validatorId;
  final Value<String> targetCid;
  final Value<int> score;
  final Value<DateTime> timestamp;
  final Value<String> signature;
  const HonorValidationsCompanion({
    this.id = const Value.absent(),
    this.validatorId = const Value.absent(),
    this.targetCid = const Value.absent(),
    this.score = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.signature = const Value.absent(),
  });
  HonorValidationsCompanion.insert({
    this.id = const Value.absent(),
    required String validatorId,
    required String targetCid,
    required int score,
    required DateTime timestamp,
    required String signature,
  })  : validatorId = Value(validatorId),
        targetCid = Value(targetCid),
        score = Value(score),
        timestamp = Value(timestamp),
        signature = Value(signature);
  static Insertable<HonorValidation> custom({
    Expression<int>? id,
    Expression<String>? validatorId,
    Expression<String>? targetCid,
    Expression<int>? score,
    Expression<DateTime>? timestamp,
    Expression<String>? signature,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (validatorId != null) 'validator_id': validatorId,
      if (targetCid != null) 'target_cid': targetCid,
      if (score != null) 'score': score,
      if (timestamp != null) 'timestamp': timestamp,
      if (signature != null) 'signature': signature,
    });
  }

  HonorValidationsCompanion copyWith(
      {Value<int>? id,
      Value<String>? validatorId,
      Value<String>? targetCid,
      Value<int>? score,
      Value<DateTime>? timestamp,
      Value<String>? signature}) {
    return HonorValidationsCompanion(
      id: id ?? this.id,
      validatorId: validatorId ?? this.validatorId,
      targetCid: targetCid ?? this.targetCid,
      score: score ?? this.score,
      timestamp: timestamp ?? this.timestamp,
      signature: signature ?? this.signature,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (validatorId.present) {
      map['validator_id'] = Variable<String>(validatorId.value);
    }
    if (targetCid.present) {
      map['target_cid'] = Variable<String>(targetCid.value);
    }
    if (score.present) {
      map['score'] = Variable<int>(score.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HonorValidationsCompanion(')
          ..write('id: $id, ')
          ..write('validatorId: $validatorId, ')
          ..write('targetCid: $targetCid, ')
          ..write('score: $score, ')
          ..write('timestamp: $timestamp, ')
          ..write('signature: $signature')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ContentManifestsTable contentManifests =
      $ContentManifestsTable(this);
  late final $ContentVersionsTable contentVersions =
      $ContentVersionsTable(this);
  late final $UserProfilesTable userProfiles = $UserProfilesTable(this);
  late final $HonorValidationsTable honorValidations =
      $HonorValidationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [contentManifests, contentVersions, userProfiles, honorValidations];
}

typedef $$ContentManifestsTableCreateCompanionBuilder
    = ContentManifestsCompanion Function({
  Value<int> id,
  required String uuid,
  required String title,
  Value<String?> author,
  Value<String?> description,
  Value<String> category,
  Value<String?> tags,
  Value<String?> metadata,
  Value<bool> isEncrypted,
  Value<String?> encryptionKey,
  required DateTime lastUpdated,
});
typedef $$ContentManifestsTableUpdateCompanionBuilder
    = ContentManifestsCompanion Function({
  Value<int> id,
  Value<String> uuid,
  Value<String> title,
  Value<String?> author,
  Value<String?> description,
  Value<String> category,
  Value<String?> tags,
  Value<String?> metadata,
  Value<bool> isEncrypted,
  Value<String?> encryptionKey,
  Value<DateTime> lastUpdated,
});

final class $$ContentManifestsTableReferences extends BaseReferences<
    _$AppDatabase, $ContentManifestsTable, ContentManifest> {
  $$ContentManifestsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ContentVersionsTable, List<ContentVersion>>
      _contentVersionsRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.contentVersions,
              aliasName: $_aliasNameGenerator(
                  db.contentManifests.id, db.contentVersions.manifestId));

  $$ContentVersionsTableProcessedTableManager get contentVersionsRefs {
    final manager =
        $$ContentVersionsTableTableManager($_db, $_db.contentVersions)
            .filter((f) => f.manifestId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_contentVersionsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ContentManifestsTableFilterComposer
    extends Composer<_$AppDatabase, $ContentManifestsTable> {
  $$ContentManifestsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get uuid => $composableBuilder(
      column: $table.uuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get metadata => $composableBuilder(
      column: $table.metadata, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEncrypted => $composableBuilder(
      column: $table.isEncrypted, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get encryptionKey => $composableBuilder(
      column: $table.encryptionKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => ColumnFilters(column));

  Expression<bool> contentVersionsRefs(
      Expression<bool> Function($$ContentVersionsTableFilterComposer f) f) {
    final $$ContentVersionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.contentVersions,
        getReferencedColumn: (t) => t.manifestId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContentVersionsTableFilterComposer(
              $db: $db,
              $table: $db.contentVersions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ContentManifestsTableOrderingComposer
    extends Composer<_$AppDatabase, $ContentManifestsTable> {
  $$ContentManifestsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get uuid => $composableBuilder(
      column: $table.uuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get category => $composableBuilder(
      column: $table.category, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tags => $composableBuilder(
      column: $table.tags, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get metadata => $composableBuilder(
      column: $table.metadata, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEncrypted => $composableBuilder(
      column: $table.isEncrypted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get encryptionKey => $composableBuilder(
      column: $table.encryptionKey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => ColumnOrderings(column));
}

class $$ContentManifestsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContentManifestsTable> {
  $$ContentManifestsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get uuid =>
      $composableBuilder(column: $table.uuid, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<bool> get isEncrypted => $composableBuilder(
      column: $table.isEncrypted, builder: (column) => column);

  GeneratedColumn<String> get encryptionKey => $composableBuilder(
      column: $table.encryptionKey, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
      column: $table.lastUpdated, builder: (column) => column);

  Expression<T> contentVersionsRefs<T extends Object>(
      Expression<T> Function($$ContentVersionsTableAnnotationComposer a) f) {
    final $$ContentVersionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.contentVersions,
        getReferencedColumn: (t) => t.manifestId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContentVersionsTableAnnotationComposer(
              $db: $db,
              $table: $db.contentVersions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ContentManifestsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ContentManifestsTable,
    ContentManifest,
    $$ContentManifestsTableFilterComposer,
    $$ContentManifestsTableOrderingComposer,
    $$ContentManifestsTableAnnotationComposer,
    $$ContentManifestsTableCreateCompanionBuilder,
    $$ContentManifestsTableUpdateCompanionBuilder,
    (ContentManifest, $$ContentManifestsTableReferences),
    ContentManifest,
    PrefetchHooks Function({bool contentVersionsRefs})> {
  $$ContentManifestsTableTableManager(
      _$AppDatabase db, $ContentManifestsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContentManifestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContentManifestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContentManifestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> uuid = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<String?> author = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String?> tags = const Value.absent(),
            Value<String?> metadata = const Value.absent(),
            Value<bool> isEncrypted = const Value.absent(),
            Value<String?> encryptionKey = const Value.absent(),
            Value<DateTime> lastUpdated = const Value.absent(),
          }) =>
              ContentManifestsCompanion(
            id: id,
            uuid: uuid,
            title: title,
            author: author,
            description: description,
            category: category,
            tags: tags,
            metadata: metadata,
            isEncrypted: isEncrypted,
            encryptionKey: encryptionKey,
            lastUpdated: lastUpdated,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String uuid,
            required String title,
            Value<String?> author = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String?> tags = const Value.absent(),
            Value<String?> metadata = const Value.absent(),
            Value<bool> isEncrypted = const Value.absent(),
            Value<String?> encryptionKey = const Value.absent(),
            required DateTime lastUpdated,
          }) =>
              ContentManifestsCompanion.insert(
            id: id,
            uuid: uuid,
            title: title,
            author: author,
            description: description,
            category: category,
            tags: tags,
            metadata: metadata,
            isEncrypted: isEncrypted,
            encryptionKey: encryptionKey,
            lastUpdated: lastUpdated,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ContentManifestsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({contentVersionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (contentVersionsRefs) db.contentVersions
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (contentVersionsRefs)
                    await $_getPrefetchedData<ContentManifest,
                            $ContentManifestsTable, ContentVersion>(
                        currentTable: table,
                        referencedTable: $$ContentManifestsTableReferences
                            ._contentVersionsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ContentManifestsTableReferences(db, table, p0)
                                .contentVersionsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.manifestId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ContentManifestsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ContentManifestsTable,
    ContentManifest,
    $$ContentManifestsTableFilterComposer,
    $$ContentManifestsTableOrderingComposer,
    $$ContentManifestsTableAnnotationComposer,
    $$ContentManifestsTableCreateCompanionBuilder,
    $$ContentManifestsTableUpdateCompanionBuilder,
    (ContentManifest, $$ContentManifestsTableReferences),
    ContentManifest,
    PrefetchHooks Function({bool contentVersionsRefs})>;
typedef $$ContentVersionsTableCreateCompanionBuilder = ContentVersionsCompanion
    Function({
  Value<int> id,
  required int manifestId,
  required String cid,
  Value<String> language,
  Value<String> format,
  required int sizeBytes,
  Value<int> peerCount,
  Value<bool> isPinned,
  Value<DateTime?> lastHealthCheck,
  required DateTime createdData,
});
typedef $$ContentVersionsTableUpdateCompanionBuilder = ContentVersionsCompanion
    Function({
  Value<int> id,
  Value<int> manifestId,
  Value<String> cid,
  Value<String> language,
  Value<String> format,
  Value<int> sizeBytes,
  Value<int> peerCount,
  Value<bool> isPinned,
  Value<DateTime?> lastHealthCheck,
  Value<DateTime> createdData,
});

final class $$ContentVersionsTableReferences extends BaseReferences<
    _$AppDatabase, $ContentVersionsTable, ContentVersion> {
  $$ContentVersionsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ContentManifestsTable _manifestIdTable(_$AppDatabase db) =>
      db.contentManifests.createAlias($_aliasNameGenerator(
          db.contentVersions.manifestId, db.contentManifests.id));

  $$ContentManifestsTableProcessedTableManager get manifestId {
    final $_column = $_itemColumn<int>('manifest_id')!;

    final manager =
        $$ContentManifestsTableTableManager($_db, $_db.contentManifests)
            .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manifestIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ContentVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $ContentVersionsTable> {
  $$ContentVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get language => $composableBuilder(
      column: $table.language, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get peerCount => $composableBuilder(
      column: $table.peerCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastHealthCheck => $composableBuilder(
      column: $table.lastHealthCheck,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdData => $composableBuilder(
      column: $table.createdData, builder: (column) => ColumnFilters(column));

  $$ContentManifestsTableFilterComposer get manifestId {
    final $$ContentManifestsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.manifestId,
        referencedTable: $db.contentManifests,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContentManifestsTableFilterComposer(
              $db: $db,
              $table: $db.contentManifests,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ContentVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ContentVersionsTable> {
  $$ContentVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get language => $composableBuilder(
      column: $table.language, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get format => $composableBuilder(
      column: $table.format, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get peerCount => $composableBuilder(
      column: $table.peerCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastHealthCheck => $composableBuilder(
      column: $table.lastHealthCheck,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdData => $composableBuilder(
      column: $table.createdData, builder: (column) => ColumnOrderings(column));

  $$ContentManifestsTableOrderingComposer get manifestId {
    final $$ContentManifestsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.manifestId,
        referencedTable: $db.contentManifests,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContentManifestsTableOrderingComposer(
              $db: $db,
              $table: $db.contentManifests,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ContentVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ContentVersionsTable> {
  $$ContentVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cid =>
      $composableBuilder(column: $table.cid, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<int> get peerCount =>
      $composableBuilder(column: $table.peerCount, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<DateTime> get lastHealthCheck => $composableBuilder(
      column: $table.lastHealthCheck, builder: (column) => column);

  GeneratedColumn<DateTime> get createdData => $composableBuilder(
      column: $table.createdData, builder: (column) => column);

  $$ContentManifestsTableAnnotationComposer get manifestId {
    final $$ContentManifestsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.manifestId,
        referencedTable: $db.contentManifests,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ContentManifestsTableAnnotationComposer(
              $db: $db,
              $table: $db.contentManifests,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ContentVersionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ContentVersionsTable,
    ContentVersion,
    $$ContentVersionsTableFilterComposer,
    $$ContentVersionsTableOrderingComposer,
    $$ContentVersionsTableAnnotationComposer,
    $$ContentVersionsTableCreateCompanionBuilder,
    $$ContentVersionsTableUpdateCompanionBuilder,
    (ContentVersion, $$ContentVersionsTableReferences),
    ContentVersion,
    PrefetchHooks Function({bool manifestId})> {
  $$ContentVersionsTableTableManager(
      _$AppDatabase db, $ContentVersionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContentVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContentVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContentVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> manifestId = const Value.absent(),
            Value<String> cid = const Value.absent(),
            Value<String> language = const Value.absent(),
            Value<String> format = const Value.absent(),
            Value<int> sizeBytes = const Value.absent(),
            Value<int> peerCount = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<DateTime?> lastHealthCheck = const Value.absent(),
            Value<DateTime> createdData = const Value.absent(),
          }) =>
              ContentVersionsCompanion(
            id: id,
            manifestId: manifestId,
            cid: cid,
            language: language,
            format: format,
            sizeBytes: sizeBytes,
            peerCount: peerCount,
            isPinned: isPinned,
            lastHealthCheck: lastHealthCheck,
            createdData: createdData,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required int manifestId,
            required String cid,
            Value<String> language = const Value.absent(),
            Value<String> format = const Value.absent(),
            required int sizeBytes,
            Value<int> peerCount = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<DateTime?> lastHealthCheck = const Value.absent(),
            required DateTime createdData,
          }) =>
              ContentVersionsCompanion.insert(
            id: id,
            manifestId: manifestId,
            cid: cid,
            language: language,
            format: format,
            sizeBytes: sizeBytes,
            peerCount: peerCount,
            isPinned: isPinned,
            lastHealthCheck: lastHealthCheck,
            createdData: createdData,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$ContentVersionsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({manifestId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (manifestId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.manifestId,
                    referencedTable:
                        $$ContentVersionsTableReferences._manifestIdTable(db),
                    referencedColumn: $$ContentVersionsTableReferences
                        ._manifestIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ContentVersionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ContentVersionsTable,
    ContentVersion,
    $$ContentVersionsTableFilterComposer,
    $$ContentVersionsTableOrderingComposer,
    $$ContentVersionsTableAnnotationComposer,
    $$ContentVersionsTableCreateCompanionBuilder,
    $$ContentVersionsTableUpdateCompanionBuilder,
    (ContentVersion, $$ContentVersionsTableReferences),
    ContentVersion,
    PrefetchHooks Function({bool manifestId})>;
typedef $$UserProfilesTableCreateCompanionBuilder = UserProfilesCompanion
    Function({
  required String publicKey,
  Value<int> reputation,
  required DateTime lastActive,
  Value<int> rowid,
});
typedef $$UserProfilesTableUpdateCompanionBuilder = UserProfilesCompanion
    Function({
  Value<String> publicKey,
  Value<int> reputation,
  Value<DateTime> lastActive,
  Value<int> rowid,
});

class $$UserProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $UserProfilesTable> {
  $$UserProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get publicKey => $composableBuilder(
      column: $table.publicKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get reputation => $composableBuilder(
      column: $table.reputation, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastActive => $composableBuilder(
      column: $table.lastActive, builder: (column) => ColumnFilters(column));
}

class $$UserProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $UserProfilesTable> {
  $$UserProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get publicKey => $composableBuilder(
      column: $table.publicKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get reputation => $composableBuilder(
      column: $table.reputation, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastActive => $composableBuilder(
      column: $table.lastActive, builder: (column) => ColumnOrderings(column));
}

class $$UserProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserProfilesTable> {
  $$UserProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<int> get reputation => $composableBuilder(
      column: $table.reputation, builder: (column) => column);

  GeneratedColumn<DateTime> get lastActive => $composableBuilder(
      column: $table.lastActive, builder: (column) => column);
}

class $$UserProfilesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UserProfilesTable,
    UserProfile,
    $$UserProfilesTableFilterComposer,
    $$UserProfilesTableOrderingComposer,
    $$UserProfilesTableAnnotationComposer,
    $$UserProfilesTableCreateCompanionBuilder,
    $$UserProfilesTableUpdateCompanionBuilder,
    (
      UserProfile,
      BaseReferences<_$AppDatabase, $UserProfilesTable, UserProfile>
    ),
    UserProfile,
    PrefetchHooks Function()> {
  $$UserProfilesTableTableManager(_$AppDatabase db, $UserProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> publicKey = const Value.absent(),
            Value<int> reputation = const Value.absent(),
            Value<DateTime> lastActive = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UserProfilesCompanion(
            publicKey: publicKey,
            reputation: reputation,
            lastActive: lastActive,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String publicKey,
            Value<int> reputation = const Value.absent(),
            required DateTime lastActive,
            Value<int> rowid = const Value.absent(),
          }) =>
              UserProfilesCompanion.insert(
            publicKey: publicKey,
            reputation: reputation,
            lastActive: lastActive,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$UserProfilesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $UserProfilesTable,
    UserProfile,
    $$UserProfilesTableFilterComposer,
    $$UserProfilesTableOrderingComposer,
    $$UserProfilesTableAnnotationComposer,
    $$UserProfilesTableCreateCompanionBuilder,
    $$UserProfilesTableUpdateCompanionBuilder,
    (
      UserProfile,
      BaseReferences<_$AppDatabase, $UserProfilesTable, UserProfile>
    ),
    UserProfile,
    PrefetchHooks Function()>;
typedef $$HonorValidationsTableCreateCompanionBuilder
    = HonorValidationsCompanion Function({
  Value<int> id,
  required String validatorId,
  required String targetCid,
  required int score,
  required DateTime timestamp,
  required String signature,
});
typedef $$HonorValidationsTableUpdateCompanionBuilder
    = HonorValidationsCompanion Function({
  Value<int> id,
  Value<String> validatorId,
  Value<String> targetCid,
  Value<int> score,
  Value<DateTime> timestamp,
  Value<String> signature,
});

class $$HonorValidationsTableFilterComposer
    extends Composer<_$AppDatabase, $HonorValidationsTable> {
  $$HonorValidationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get validatorId => $composableBuilder(
      column: $table.validatorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get targetCid => $composableBuilder(
      column: $table.targetCid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get score => $composableBuilder(
      column: $table.score, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get signature => $composableBuilder(
      column: $table.signature, builder: (column) => ColumnFilters(column));
}

class $$HonorValidationsTableOrderingComposer
    extends Composer<_$AppDatabase, $HonorValidationsTable> {
  $$HonorValidationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get validatorId => $composableBuilder(
      column: $table.validatorId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get targetCid => $composableBuilder(
      column: $table.targetCid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get score => $composableBuilder(
      column: $table.score, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get signature => $composableBuilder(
      column: $table.signature, builder: (column) => ColumnOrderings(column));
}

class $$HonorValidationsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HonorValidationsTable> {
  $$HonorValidationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get validatorId => $composableBuilder(
      column: $table.validatorId, builder: (column) => column);

  GeneratedColumn<String> get targetCid =>
      $composableBuilder(column: $table.targetCid, builder: (column) => column);

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);
}

class $$HonorValidationsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $HonorValidationsTable,
    HonorValidation,
    $$HonorValidationsTableFilterComposer,
    $$HonorValidationsTableOrderingComposer,
    $$HonorValidationsTableAnnotationComposer,
    $$HonorValidationsTableCreateCompanionBuilder,
    $$HonorValidationsTableUpdateCompanionBuilder,
    (
      HonorValidation,
      BaseReferences<_$AppDatabase, $HonorValidationsTable, HonorValidation>
    ),
    HonorValidation,
    PrefetchHooks Function()> {
  $$HonorValidationsTableTableManager(
      _$AppDatabase db, $HonorValidationsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HonorValidationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HonorValidationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HonorValidationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> validatorId = const Value.absent(),
            Value<String> targetCid = const Value.absent(),
            Value<int> score = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
            Value<String> signature = const Value.absent(),
          }) =>
              HonorValidationsCompanion(
            id: id,
            validatorId: validatorId,
            targetCid: targetCid,
            score: score,
            timestamp: timestamp,
            signature: signature,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String validatorId,
            required String targetCid,
            required int score,
            required DateTime timestamp,
            required String signature,
          }) =>
              HonorValidationsCompanion.insert(
            id: id,
            validatorId: validatorId,
            targetCid: targetCid,
            score: score,
            timestamp: timestamp,
            signature: signature,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$HonorValidationsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $HonorValidationsTable,
    HonorValidation,
    $$HonorValidationsTableFilterComposer,
    $$HonorValidationsTableOrderingComposer,
    $$HonorValidationsTableAnnotationComposer,
    $$HonorValidationsTableCreateCompanionBuilder,
    $$HonorValidationsTableUpdateCompanionBuilder,
    (
      HonorValidation,
      BaseReferences<_$AppDatabase, $HonorValidationsTable, HonorValidation>
    ),
    HonorValidation,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ContentManifestsTableTableManager get contentManifests =>
      $$ContentManifestsTableTableManager(_db, _db.contentManifests);
  $$ContentVersionsTableTableManager get contentVersions =>
      $$ContentVersionsTableTableManager(_db, _db.contentVersions);
  $$UserProfilesTableTableManager get userProfiles =>
      $$UserProfilesTableTableManager(_db, _db.userProfiles);
  $$HonorValidationsTableTableManager get honorValidations =>
      $$HonorValidationsTableTableManager(_db, _db.honorValidations);
}
