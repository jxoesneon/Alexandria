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
  static const VerificationMeta _publisherPubkeyMeta =
      const VerificationMeta('publisherPubkey');
  @override
  late final GeneratedColumn<String> publisherPubkey = GeneratedColumn<String>(
      'publisher_pubkey', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _signatureMeta =
      const VerificationMeta('signature');
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
      'signature', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _flaggedReasonMeta =
      const VerificationMeta('flaggedReason');
  @override
  late final GeneratedColumn<String> flaggedReason = GeneratedColumn<String>(
      'flagged_reason', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
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
        createdData,
        publisherPubkey,
        signature,
        flaggedReason
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
    if (data.containsKey('publisher_pubkey')) {
      context.handle(
          _publisherPubkeyMeta,
          publisherPubkey.isAcceptableOrUnknown(
              data['publisher_pubkey']!, _publisherPubkeyMeta));
    }
    if (data.containsKey('signature')) {
      context.handle(_signatureMeta,
          signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta));
    }
    if (data.containsKey('flagged_reason')) {
      context.handle(
          _flaggedReasonMeta,
          flaggedReason.isAcceptableOrUnknown(
              data['flagged_reason']!, _flaggedReasonMeta));
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
      publisherPubkey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}publisher_pubkey']),
      signature: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}signature']),
      flaggedReason: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}flagged_reason']),
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
  final String? publisherPubkey;
  final String? signature;
  final String? flaggedReason;
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
      required this.createdData,
      this.publisherPubkey,
      this.signature,
      this.flaggedReason});
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
    if (!nullToAbsent || publisherPubkey != null) {
      map['publisher_pubkey'] = Variable<String>(publisherPubkey);
    }
    if (!nullToAbsent || signature != null) {
      map['signature'] = Variable<String>(signature);
    }
    if (!nullToAbsent || flaggedReason != null) {
      map['flagged_reason'] = Variable<String>(flaggedReason);
    }
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
      publisherPubkey: publisherPubkey == null && nullToAbsent
          ? const Value.absent()
          : Value(publisherPubkey),
      signature: signature == null && nullToAbsent
          ? const Value.absent()
          : Value(signature),
      flaggedReason: flaggedReason == null && nullToAbsent
          ? const Value.absent()
          : Value(flaggedReason),
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
      publisherPubkey: serializer.fromJson<String?>(json['publisherPubkey']),
      signature: serializer.fromJson<String?>(json['signature']),
      flaggedReason: serializer.fromJson<String?>(json['flaggedReason']),
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
      'publisherPubkey': serializer.toJson<String?>(publisherPubkey),
      'signature': serializer.toJson<String?>(signature),
      'flaggedReason': serializer.toJson<String?>(flaggedReason),
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
          DateTime? createdData,
          Value<String?> publisherPubkey = const Value.absent(),
          Value<String?> signature = const Value.absent(),
          Value<String?> flaggedReason = const Value.absent()}) =>
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
        publisherPubkey: publisherPubkey.present
            ? publisherPubkey.value
            : this.publisherPubkey,
        signature: signature.present ? signature.value : this.signature,
        flaggedReason:
            flaggedReason.present ? flaggedReason.value : this.flaggedReason,
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
      publisherPubkey: data.publisherPubkey.present
          ? data.publisherPubkey.value
          : this.publisherPubkey,
      signature: data.signature.present ? data.signature.value : this.signature,
      flaggedReason: data.flaggedReason.present
          ? data.flaggedReason.value
          : this.flaggedReason,
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
          ..write('createdData: $createdData, ')
          ..write('publisherPubkey: $publisherPubkey, ')
          ..write('signature: $signature, ')
          ..write('flaggedReason: $flaggedReason')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      manifestId,
      cid,
      language,
      format,
      sizeBytes,
      peerCount,
      isPinned,
      lastHealthCheck,
      createdData,
      publisherPubkey,
      signature,
      flaggedReason);
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
          other.createdData == this.createdData &&
          other.publisherPubkey == this.publisherPubkey &&
          other.signature == this.signature &&
          other.flaggedReason == this.flaggedReason);
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
  final Value<String?> publisherPubkey;
  final Value<String?> signature;
  final Value<String?> flaggedReason;
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
    this.publisherPubkey = const Value.absent(),
    this.signature = const Value.absent(),
    this.flaggedReason = const Value.absent(),
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
    this.publisherPubkey = const Value.absent(),
    this.signature = const Value.absent(),
    this.flaggedReason = const Value.absent(),
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
    Expression<String>? publisherPubkey,
    Expression<String>? signature,
    Expression<String>? flaggedReason,
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
      if (publisherPubkey != null) 'publisher_pubkey': publisherPubkey,
      if (signature != null) 'signature': signature,
      if (flaggedReason != null) 'flagged_reason': flaggedReason,
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
      Value<DateTime>? createdData,
      Value<String?>? publisherPubkey,
      Value<String?>? signature,
      Value<String?>? flaggedReason}) {
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
      publisherPubkey: publisherPubkey ?? this.publisherPubkey,
      signature: signature ?? this.signature,
      flaggedReason: flaggedReason ?? this.flaggedReason,
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
    if (publisherPubkey.present) {
      map['publisher_pubkey'] = Variable<String>(publisherPubkey.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    if (flaggedReason.present) {
      map['flagged_reason'] = Variable<String>(flaggedReason.value);
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
          ..write('createdData: $createdData, ')
          ..write('publisherPubkey: $publisherPubkey, ')
          ..write('signature: $signature, ')
          ..write('flaggedReason: $flaggedReason')
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

class $CreditTransactionsTable extends CreditTransactions
    with TableInfo<$CreditTransactionsTable, CreditTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CreditTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _referenceIdMeta =
      const VerificationMeta('referenceId');
  @override
  late final GeneratedColumn<String> referenceId = GeneratedColumn<String>(
      'reference_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
      'hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isAttestedMeta =
      const VerificationMeta('isAttested');
  @override
  late final GeneratedColumn<bool> isAttested = GeneratedColumn<bool>(
      'is_attested', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_attested" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, timestamp, type, amount, description, referenceId, hash, isAttested];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'credit_transactions';
  @override
  VerificationContext validateIntegrity(Insertable<CreditTransaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('reference_id')) {
      context.handle(
          _referenceIdMeta,
          referenceId.isAcceptableOrUnknown(
              data['reference_id']!, _referenceIdMeta));
    }
    if (data.containsKey('hash')) {
      context.handle(
          _hashMeta, hash.isAcceptableOrUnknown(data['hash']!, _hashMeta));
    } else if (isInserting) {
      context.missing(_hashMeta);
    }
    if (data.containsKey('is_attested')) {
      context.handle(
          _isAttestedMeta,
          isAttested.isAcceptableOrUnknown(
              data['is_attested']!, _isAttestedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CreditTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CreditTransaction(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      referenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference_id']),
      hash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}hash'])!,
      isAttested: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_attested'])!,
    );
  }

  @override
  $CreditTransactionsTable createAlias(String alias) {
    return $CreditTransactionsTable(attachedDatabase, alias);
  }
}

class CreditTransaction extends DataClass
    implements Insertable<CreditTransaction> {
  final String id;
  final DateTime timestamp;
  final String type;
  final double amount;
  final String description;
  final String? referenceId;
  final String hash;
  final bool isAttested;
  const CreditTransaction(
      {required this.id,
      required this.timestamp,
      required this.type,
      required this.amount,
      required this.description,
      this.referenceId,
      required this.hash,
      required this.isAttested});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['timestamp'] = Variable<DateTime>(timestamp);
    map['type'] = Variable<String>(type);
    map['amount'] = Variable<double>(amount);
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || referenceId != null) {
      map['reference_id'] = Variable<String>(referenceId);
    }
    map['hash'] = Variable<String>(hash);
    map['is_attested'] = Variable<bool>(isAttested);
    return map;
  }

  CreditTransactionsCompanion toCompanion(bool nullToAbsent) {
    return CreditTransactionsCompanion(
      id: Value(id),
      timestamp: Value(timestamp),
      type: Value(type),
      amount: Value(amount),
      description: Value(description),
      referenceId: referenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceId),
      hash: Value(hash),
      isAttested: Value(isAttested),
    );
  }

  factory CreditTransaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CreditTransaction(
      id: serializer.fromJson<String>(json['id']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      type: serializer.fromJson<String>(json['type']),
      amount: serializer.fromJson<double>(json['amount']),
      description: serializer.fromJson<String>(json['description']),
      referenceId: serializer.fromJson<String?>(json['referenceId']),
      hash: serializer.fromJson<String>(json['hash']),
      isAttested: serializer.fromJson<bool>(json['isAttested']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'type': serializer.toJson<String>(type),
      'amount': serializer.toJson<double>(amount),
      'description': serializer.toJson<String>(description),
      'referenceId': serializer.toJson<String?>(referenceId),
      'hash': serializer.toJson<String>(hash),
      'isAttested': serializer.toJson<bool>(isAttested),
    };
  }

  CreditTransaction copyWith(
          {String? id,
          DateTime? timestamp,
          String? type,
          double? amount,
          String? description,
          Value<String?> referenceId = const Value.absent(),
          String? hash,
          bool? isAttested}) =>
      CreditTransaction(
        id: id ?? this.id,
        timestamp: timestamp ?? this.timestamp,
        type: type ?? this.type,
        amount: amount ?? this.amount,
        description: description ?? this.description,
        referenceId: referenceId.present ? referenceId.value : this.referenceId,
        hash: hash ?? this.hash,
        isAttested: isAttested ?? this.isAttested,
      );
  CreditTransaction copyWithCompanion(CreditTransactionsCompanion data) {
    return CreditTransaction(
      id: data.id.present ? data.id.value : this.id,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      type: data.type.present ? data.type.value : this.type,
      amount: data.amount.present ? data.amount.value : this.amount,
      description:
          data.description.present ? data.description.value : this.description,
      referenceId:
          data.referenceId.present ? data.referenceId.value : this.referenceId,
      hash: data.hash.present ? data.hash.value : this.hash,
      isAttested:
          data.isAttested.present ? data.isAttested.value : this.isAttested,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CreditTransaction(')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('description: $description, ')
          ..write('referenceId: $referenceId, ')
          ..write('hash: $hash, ')
          ..write('isAttested: $isAttested')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, timestamp, type, amount, description, referenceId, hash, isAttested);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CreditTransaction &&
          other.id == this.id &&
          other.timestamp == this.timestamp &&
          other.type == this.type &&
          other.amount == this.amount &&
          other.description == this.description &&
          other.referenceId == this.referenceId &&
          other.hash == this.hash &&
          other.isAttested == this.isAttested);
}

class CreditTransactionsCompanion extends UpdateCompanion<CreditTransaction> {
  final Value<String> id;
  final Value<DateTime> timestamp;
  final Value<String> type;
  final Value<double> amount;
  final Value<String> description;
  final Value<String?> referenceId;
  final Value<String> hash;
  final Value<bool> isAttested;
  final Value<int> rowid;
  const CreditTransactionsCompanion({
    this.id = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.type = const Value.absent(),
    this.amount = const Value.absent(),
    this.description = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.hash = const Value.absent(),
    this.isAttested = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CreditTransactionsCompanion.insert({
    required String id,
    required DateTime timestamp,
    required String type,
    required double amount,
    required String description,
    this.referenceId = const Value.absent(),
    required String hash,
    this.isAttested = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        timestamp = Value(timestamp),
        type = Value(type),
        amount = Value(amount),
        description = Value(description),
        hash = Value(hash);
  static Insertable<CreditTransaction> custom({
    Expression<String>? id,
    Expression<DateTime>? timestamp,
    Expression<String>? type,
    Expression<double>? amount,
    Expression<String>? description,
    Expression<String>? referenceId,
    Expression<String>? hash,
    Expression<bool>? isAttested,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (timestamp != null) 'timestamp': timestamp,
      if (type != null) 'type': type,
      if (amount != null) 'amount': amount,
      if (description != null) 'description': description,
      if (referenceId != null) 'reference_id': referenceId,
      if (hash != null) 'hash': hash,
      if (isAttested != null) 'is_attested': isAttested,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CreditTransactionsCompanion copyWith(
      {Value<String>? id,
      Value<DateTime>? timestamp,
      Value<String>? type,
      Value<double>? amount,
      Value<String>? description,
      Value<String?>? referenceId,
      Value<String>? hash,
      Value<bool>? isAttested,
      Value<int>? rowid}) {
    return CreditTransactionsCompanion(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      referenceId: referenceId ?? this.referenceId,
      hash: hash ?? this.hash,
      isAttested: isAttested ?? this.isAttested,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<String>(referenceId.value);
    }
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (isAttested.present) {
      map['is_attested'] = Variable<bool>(isAttested.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CreditTransactionsCompanion(')
          ..write('id: $id, ')
          ..write('timestamp: $timestamp, ')
          ..write('type: $type, ')
          ..write('amount: $amount, ')
          ..write('description: $description, ')
          ..write('referenceId: $referenceId, ')
          ..write('hash: $hash, ')
          ..write('isAttested: $isAttested, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DailyMintedTable extends DailyMinted
    with TableInfo<$DailyMintedTable, DailyMintedData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyMintedTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayKeyMeta = const VerificationMeta('dayKey');
  @override
  late final GeneratedColumn<String> dayKey = GeneratedColumn<String>(
      'day_key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _creditTypeMeta =
      const VerificationMeta('creditType');
  @override
  late final GeneratedColumn<String> creditType = GeneratedColumn<String>(
      'credit_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [dayKey, creditType, amount];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_minted';
  @override
  VerificationContext validateIntegrity(Insertable<DailyMintedData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day_key')) {
      context.handle(_dayKeyMeta,
          dayKey.isAcceptableOrUnknown(data['day_key']!, _dayKeyMeta));
    } else if (isInserting) {
      context.missing(_dayKeyMeta);
    }
    if (data.containsKey('credit_type')) {
      context.handle(
          _creditTypeMeta,
          creditType.isAcceptableOrUnknown(
              data['credit_type']!, _creditTypeMeta));
    } else if (isInserting) {
      context.missing(_creditTypeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {dayKey, creditType};
  @override
  DailyMintedData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyMintedData(
      dayKey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}day_key'])!,
      creditType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}credit_type'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
    );
  }

  @override
  $DailyMintedTable createAlias(String alias) {
    return $DailyMintedTable(attachedDatabase, alias);
  }
}

class DailyMintedData extends DataClass implements Insertable<DailyMintedData> {
  final String dayKey;
  final String creditType;
  final double amount;
  const DailyMintedData(
      {required this.dayKey, required this.creditType, required this.amount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day_key'] = Variable<String>(dayKey);
    map['credit_type'] = Variable<String>(creditType);
    map['amount'] = Variable<double>(amount);
    return map;
  }

  DailyMintedCompanion toCompanion(bool nullToAbsent) {
    return DailyMintedCompanion(
      dayKey: Value(dayKey),
      creditType: Value(creditType),
      amount: Value(amount),
    );
  }

  factory DailyMintedData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyMintedData(
      dayKey: serializer.fromJson<String>(json['dayKey']),
      creditType: serializer.fromJson<String>(json['creditType']),
      amount: serializer.fromJson<double>(json['amount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'dayKey': serializer.toJson<String>(dayKey),
      'creditType': serializer.toJson<String>(creditType),
      'amount': serializer.toJson<double>(amount),
    };
  }

  DailyMintedData copyWith(
          {String? dayKey, String? creditType, double? amount}) =>
      DailyMintedData(
        dayKey: dayKey ?? this.dayKey,
        creditType: creditType ?? this.creditType,
        amount: amount ?? this.amount,
      );
  DailyMintedData copyWithCompanion(DailyMintedCompanion data) {
    return DailyMintedData(
      dayKey: data.dayKey.present ? data.dayKey.value : this.dayKey,
      creditType:
          data.creditType.present ? data.creditType.value : this.creditType,
      amount: data.amount.present ? data.amount.value : this.amount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyMintedData(')
          ..write('dayKey: $dayKey, ')
          ..write('creditType: $creditType, ')
          ..write('amount: $amount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(dayKey, creditType, amount);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyMintedData &&
          other.dayKey == this.dayKey &&
          other.creditType == this.creditType &&
          other.amount == this.amount);
}

class DailyMintedCompanion extends UpdateCompanion<DailyMintedData> {
  final Value<String> dayKey;
  final Value<String> creditType;
  final Value<double> amount;
  final Value<int> rowid;
  const DailyMintedCompanion({
    this.dayKey = const Value.absent(),
    this.creditType = const Value.absent(),
    this.amount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DailyMintedCompanion.insert({
    required String dayKey,
    required String creditType,
    required double amount,
    this.rowid = const Value.absent(),
  })  : dayKey = Value(dayKey),
        creditType = Value(creditType),
        amount = Value(amount);
  static Insertable<DailyMintedData> custom({
    Expression<String>? dayKey,
    Expression<String>? creditType,
    Expression<double>? amount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (dayKey != null) 'day_key': dayKey,
      if (creditType != null) 'credit_type': creditType,
      if (amount != null) 'amount': amount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DailyMintedCompanion copyWith(
      {Value<String>? dayKey,
      Value<String>? creditType,
      Value<double>? amount,
      Value<int>? rowid}) {
    return DailyMintedCompanion(
      dayKey: dayKey ?? this.dayKey,
      creditType: creditType ?? this.creditType,
      amount: amount ?? this.amount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (dayKey.present) {
      map['day_key'] = Variable<String>(dayKey.value);
    }
    if (creditType.present) {
      map['credit_type'] = Variable<String>(creditType.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyMintedCompanion(')
          ..write('dayKey: $dayKey, ')
          ..write('creditType: $creditType, ')
          ..write('amount: $amount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AwardedDoisTable extends AwardedDois
    with TableInfo<$AwardedDoisTable, AwardedDoi> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AwardedDoisTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _doiMeta = const VerificationMeta('doi');
  @override
  late final GeneratedColumn<String> doi = GeneratedColumn<String>(
      'doi', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _awardedAtMeta =
      const VerificationMeta('awardedAt');
  @override
  late final GeneratedColumn<DateTime> awardedAt = GeneratedColumn<DateTime>(
      'awarded_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _cidMeta = const VerificationMeta('cid');
  @override
  late final GeneratedColumn<String> cid = GeneratedColumn<String>(
      'cid', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [doi, awardedAt, cid];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'awarded_dois';
  @override
  VerificationContext validateIntegrity(Insertable<AwardedDoi> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('doi')) {
      context.handle(
          _doiMeta, doi.isAcceptableOrUnknown(data['doi']!, _doiMeta));
    } else if (isInserting) {
      context.missing(_doiMeta);
    }
    if (data.containsKey('awarded_at')) {
      context.handle(_awardedAtMeta,
          awardedAt.isAcceptableOrUnknown(data['awarded_at']!, _awardedAtMeta));
    } else if (isInserting) {
      context.missing(_awardedAtMeta);
    }
    if (data.containsKey('cid')) {
      context.handle(
          _cidMeta, cid.isAcceptableOrUnknown(data['cid']!, _cidMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {doi};
  @override
  AwardedDoi map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AwardedDoi(
      doi: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}doi'])!,
      awardedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}awarded_at'])!,
      cid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cid']),
    );
  }

  @override
  $AwardedDoisTable createAlias(String alias) {
    return $AwardedDoisTable(attachedDatabase, alias);
  }
}

class AwardedDoi extends DataClass implements Insertable<AwardedDoi> {
  final String doi;
  final DateTime awardedAt;
  final String? cid;
  const AwardedDoi({required this.doi, required this.awardedAt, this.cid});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['doi'] = Variable<String>(doi);
    map['awarded_at'] = Variable<DateTime>(awardedAt);
    if (!nullToAbsent || cid != null) {
      map['cid'] = Variable<String>(cid);
    }
    return map;
  }

  AwardedDoisCompanion toCompanion(bool nullToAbsent) {
    return AwardedDoisCompanion(
      doi: Value(doi),
      awardedAt: Value(awardedAt),
      cid: cid == null && nullToAbsent ? const Value.absent() : Value(cid),
    );
  }

  factory AwardedDoi.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AwardedDoi(
      doi: serializer.fromJson<String>(json['doi']),
      awardedAt: serializer.fromJson<DateTime>(json['awardedAt']),
      cid: serializer.fromJson<String?>(json['cid']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'doi': serializer.toJson<String>(doi),
      'awardedAt': serializer.toJson<DateTime>(awardedAt),
      'cid': serializer.toJson<String?>(cid),
    };
  }

  AwardedDoi copyWith(
          {String? doi,
          DateTime? awardedAt,
          Value<String?> cid = const Value.absent()}) =>
      AwardedDoi(
        doi: doi ?? this.doi,
        awardedAt: awardedAt ?? this.awardedAt,
        cid: cid.present ? cid.value : this.cid,
      );
  AwardedDoi copyWithCompanion(AwardedDoisCompanion data) {
    return AwardedDoi(
      doi: data.doi.present ? data.doi.value : this.doi,
      awardedAt: data.awardedAt.present ? data.awardedAt.value : this.awardedAt,
      cid: data.cid.present ? data.cid.value : this.cid,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AwardedDoi(')
          ..write('doi: $doi, ')
          ..write('awardedAt: $awardedAt, ')
          ..write('cid: $cid')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(doi, awardedAt, cid);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AwardedDoi &&
          other.doi == this.doi &&
          other.awardedAt == this.awardedAt &&
          other.cid == this.cid);
}

class AwardedDoisCompanion extends UpdateCompanion<AwardedDoi> {
  final Value<String> doi;
  final Value<DateTime> awardedAt;
  final Value<String?> cid;
  final Value<int> rowid;
  const AwardedDoisCompanion({
    this.doi = const Value.absent(),
    this.awardedAt = const Value.absent(),
    this.cid = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AwardedDoisCompanion.insert({
    required String doi,
    required DateTime awardedAt,
    this.cid = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : doi = Value(doi),
        awardedAt = Value(awardedAt);
  static Insertable<AwardedDoi> custom({
    Expression<String>? doi,
    Expression<DateTime>? awardedAt,
    Expression<String>? cid,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (doi != null) 'doi': doi,
      if (awardedAt != null) 'awarded_at': awardedAt,
      if (cid != null) 'cid': cid,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AwardedDoisCompanion copyWith(
      {Value<String>? doi,
      Value<DateTime>? awardedAt,
      Value<String?>? cid,
      Value<int>? rowid}) {
    return AwardedDoisCompanion(
      doi: doi ?? this.doi,
      awardedAt: awardedAt ?? this.awardedAt,
      cid: cid ?? this.cid,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (doi.present) {
      map['doi'] = Variable<String>(doi.value);
    }
    if (awardedAt.present) {
      map['awarded_at'] = Variable<DateTime>(awardedAt.value);
    }
    if (cid.present) {
      map['cid'] = Variable<String>(cid.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AwardedDoisCompanion(')
          ..write('doi: $doi, ')
          ..write('awardedAt: $awardedAt, ')
          ..write('cid: $cid, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkReceiptsTable extends WorkReceipts
    with TableInfo<$WorkReceiptsTable, WorkReceipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _receiptIdMeta =
      const VerificationMeta('receiptId');
  @override
  late final GeneratedColumn<String> receiptId = GeneratedColumn<String>(
      'receipt_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _vMeta = const VerificationMeta('v');
  @override
  late final GeneratedColumn<int> v = GeneratedColumn<int>(
      'v', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _workTypeMeta =
      const VerificationMeta('workType');
  @override
  late final GeneratedColumn<String> workType = GeneratedColumn<String>(
      'work_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _proverPubkeyMeta =
      const VerificationMeta('proverPubkey');
  @override
  late final GeneratedColumn<String> proverPubkey = GeneratedColumn<String>(
      'prover_pubkey', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _verifierPubkeyMeta =
      const VerificationMeta('verifierPubkey');
  @override
  late final GeneratedColumn<String> verifierPubkey = GeneratedColumn<String>(
      'verifier_pubkey', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cidMeta = const VerificationMeta('cid');
  @override
  late final GeneratedColumn<String> cid = GeneratedColumn<String>(
      'cid', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _chunkIndicesMeta =
      const VerificationMeta('chunkIndices');
  @override
  late final GeneratedColumn<String> chunkIndices = GeneratedColumn<String>(
      'chunk_indices', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _challengeNonceMeta =
      const VerificationMeta('challengeNonce');
  @override
  late final GeneratedColumn<String> challengeNonce = GeneratedColumn<String>(
      'challenge_nonce', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _responseTagMeta =
      const VerificationMeta('responseTag');
  @override
  late final GeneratedColumn<String> responseTag = GeneratedColumn<String>(
      'response_tag', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _workUnitsMeta =
      const VerificationMeta('workUnits');
  @override
  late final GeneratedColumn<double> workUnits = GeneratedColumn<double>(
      'work_units', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<String> epoch = GeneratedColumn<String>(
      'epoch', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _expiresAtMeta =
      const VerificationMeta('expiresAt');
  @override
  late final GeneratedColumn<int> expiresAt = GeneratedColumn<int>(
      'expires_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _evidenceHashMeta =
      const VerificationMeta('evidenceHash');
  @override
  late final GeneratedColumn<String> evidenceHash = GeneratedColumn<String>(
      'evidence_hash', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _verifierSigMeta =
      const VerificationMeta('verifierSig');
  @override
  late final GeneratedColumn<String> verifierSig = GeneratedColumn<String>(
      'verifier_sig', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _proverSigMeta =
      const VerificationMeta('proverSig');
  @override
  late final GeneratedColumn<String> proverSig = GeneratedColumn<String>(
      'prover_sig', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _spentMeta = const VerificationMeta('spent');
  @override
  late final GeneratedColumn<bool> spent = GeneratedColumn<bool>(
      'spent', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("spent" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        receiptId,
        v,
        workType,
        proverPubkey,
        verifierPubkey,
        cid,
        chunkIndices,
        challengeNonce,
        responseTag,
        workUnits,
        amount,
        epoch,
        expiresAt,
        evidenceHash,
        verifierSig,
        proverSig,
        spent,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'work_receipts';
  @override
  VerificationContext validateIntegrity(Insertable<WorkReceipt> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('receipt_id')) {
      context.handle(_receiptIdMeta,
          receiptId.isAcceptableOrUnknown(data['receipt_id']!, _receiptIdMeta));
    } else if (isInserting) {
      context.missing(_receiptIdMeta);
    }
    if (data.containsKey('v')) {
      context.handle(_vMeta, v.isAcceptableOrUnknown(data['v']!, _vMeta));
    }
    if (data.containsKey('work_type')) {
      context.handle(_workTypeMeta,
          workType.isAcceptableOrUnknown(data['work_type']!, _workTypeMeta));
    } else if (isInserting) {
      context.missing(_workTypeMeta);
    }
    if (data.containsKey('prover_pubkey')) {
      context.handle(
          _proverPubkeyMeta,
          proverPubkey.isAcceptableOrUnknown(
              data['prover_pubkey']!, _proverPubkeyMeta));
    } else if (isInserting) {
      context.missing(_proverPubkeyMeta);
    }
    if (data.containsKey('verifier_pubkey')) {
      context.handle(
          _verifierPubkeyMeta,
          verifierPubkey.isAcceptableOrUnknown(
              data['verifier_pubkey']!, _verifierPubkeyMeta));
    } else if (isInserting) {
      context.missing(_verifierPubkeyMeta);
    }
    if (data.containsKey('cid')) {
      context.handle(
          _cidMeta, cid.isAcceptableOrUnknown(data['cid']!, _cidMeta));
    }
    if (data.containsKey('chunk_indices')) {
      context.handle(
          _chunkIndicesMeta,
          chunkIndices.isAcceptableOrUnknown(
              data['chunk_indices']!, _chunkIndicesMeta));
    } else if (isInserting) {
      context.missing(_chunkIndicesMeta);
    }
    if (data.containsKey('challenge_nonce')) {
      context.handle(
          _challengeNonceMeta,
          challengeNonce.isAcceptableOrUnknown(
              data['challenge_nonce']!, _challengeNonceMeta));
    } else if (isInserting) {
      context.missing(_challengeNonceMeta);
    }
    if (data.containsKey('response_tag')) {
      context.handle(
          _responseTagMeta,
          responseTag.isAcceptableOrUnknown(
              data['response_tag']!, _responseTagMeta));
    } else if (isInserting) {
      context.missing(_responseTagMeta);
    }
    if (data.containsKey('work_units')) {
      context.handle(_workUnitsMeta,
          workUnits.isAcceptableOrUnknown(data['work_units']!, _workUnitsMeta));
    } else if (isInserting) {
      context.missing(_workUnitsMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('epoch')) {
      context.handle(
          _epochMeta, epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta));
    } else if (isInserting) {
      context.missing(_epochMeta);
    }
    if (data.containsKey('expires_at')) {
      context.handle(_expiresAtMeta,
          expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta));
    } else if (isInserting) {
      context.missing(_expiresAtMeta);
    }
    if (data.containsKey('evidence_hash')) {
      context.handle(
          _evidenceHashMeta,
          evidenceHash.isAcceptableOrUnknown(
              data['evidence_hash']!, _evidenceHashMeta));
    }
    if (data.containsKey('verifier_sig')) {
      context.handle(
          _verifierSigMeta,
          verifierSig.isAcceptableOrUnknown(
              data['verifier_sig']!, _verifierSigMeta));
    } else if (isInserting) {
      context.missing(_verifierSigMeta);
    }
    if (data.containsKey('prover_sig')) {
      context.handle(_proverSigMeta,
          proverSig.isAcceptableOrUnknown(data['prover_sig']!, _proverSigMeta));
    }
    if (data.containsKey('spent')) {
      context.handle(
          _spentMeta, spent.isAcceptableOrUnknown(data['spent']!, _spentMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {receiptId};
  @override
  WorkReceipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkReceipt(
      receiptId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}receipt_id'])!,
      v: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}v'])!,
      workType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}work_type'])!,
      proverPubkey: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prover_pubkey'])!,
      verifierPubkey: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}verifier_pubkey'])!,
      cid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cid']),
      chunkIndices: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chunk_indices'])!,
      challengeNonce: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}challenge_nonce'])!,
      responseTag: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}response_tag'])!,
      workUnits: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}work_units'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      epoch: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}epoch'])!,
      expiresAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}expires_at'])!,
      evidenceHash: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}evidence_hash']),
      verifierSig: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}verifier_sig'])!,
      proverSig: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prover_sig']),
      spent: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}spent'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $WorkReceiptsTable createAlias(String alias) {
    return $WorkReceiptsTable(attachedDatabase, alias);
  }
}

class WorkReceipt extends DataClass implements Insertable<WorkReceipt> {
  final String receiptId;
  final int v;
  final String workType;
  final String proverPubkey;
  final String verifierPubkey;
  final String? cid;
  final String chunkIndices;
  final String challengeNonce;
  final String responseTag;
  final double workUnits;
  final double amount;
  final String epoch;
  final int expiresAt;
  final String? evidenceHash;
  final String verifierSig;
  final String? proverSig;
  final bool spent;
  final DateTime createdAt;
  const WorkReceipt(
      {required this.receiptId,
      required this.v,
      required this.workType,
      required this.proverPubkey,
      required this.verifierPubkey,
      this.cid,
      required this.chunkIndices,
      required this.challengeNonce,
      required this.responseTag,
      required this.workUnits,
      required this.amount,
      required this.epoch,
      required this.expiresAt,
      this.evidenceHash,
      required this.verifierSig,
      this.proverSig,
      required this.spent,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['receipt_id'] = Variable<String>(receiptId);
    map['v'] = Variable<int>(v);
    map['work_type'] = Variable<String>(workType);
    map['prover_pubkey'] = Variable<String>(proverPubkey);
    map['verifier_pubkey'] = Variable<String>(verifierPubkey);
    if (!nullToAbsent || cid != null) {
      map['cid'] = Variable<String>(cid);
    }
    map['chunk_indices'] = Variable<String>(chunkIndices);
    map['challenge_nonce'] = Variable<String>(challengeNonce);
    map['response_tag'] = Variable<String>(responseTag);
    map['work_units'] = Variable<double>(workUnits);
    map['amount'] = Variable<double>(amount);
    map['epoch'] = Variable<String>(epoch);
    map['expires_at'] = Variable<int>(expiresAt);
    if (!nullToAbsent || evidenceHash != null) {
      map['evidence_hash'] = Variable<String>(evidenceHash);
    }
    map['verifier_sig'] = Variable<String>(verifierSig);
    if (!nullToAbsent || proverSig != null) {
      map['prover_sig'] = Variable<String>(proverSig);
    }
    map['spent'] = Variable<bool>(spent);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  WorkReceiptsCompanion toCompanion(bool nullToAbsent) {
    return WorkReceiptsCompanion(
      receiptId: Value(receiptId),
      v: Value(v),
      workType: Value(workType),
      proverPubkey: Value(proverPubkey),
      verifierPubkey: Value(verifierPubkey),
      cid: cid == null && nullToAbsent ? const Value.absent() : Value(cid),
      chunkIndices: Value(chunkIndices),
      challengeNonce: Value(challengeNonce),
      responseTag: Value(responseTag),
      workUnits: Value(workUnits),
      amount: Value(amount),
      epoch: Value(epoch),
      expiresAt: Value(expiresAt),
      evidenceHash: evidenceHash == null && nullToAbsent
          ? const Value.absent()
          : Value(evidenceHash),
      verifierSig: Value(verifierSig),
      proverSig: proverSig == null && nullToAbsent
          ? const Value.absent()
          : Value(proverSig),
      spent: Value(spent),
      createdAt: Value(createdAt),
    );
  }

  factory WorkReceipt.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkReceipt(
      receiptId: serializer.fromJson<String>(json['receiptId']),
      v: serializer.fromJson<int>(json['v']),
      workType: serializer.fromJson<String>(json['workType']),
      proverPubkey: serializer.fromJson<String>(json['proverPubkey']),
      verifierPubkey: serializer.fromJson<String>(json['verifierPubkey']),
      cid: serializer.fromJson<String?>(json['cid']),
      chunkIndices: serializer.fromJson<String>(json['chunkIndices']),
      challengeNonce: serializer.fromJson<String>(json['challengeNonce']),
      responseTag: serializer.fromJson<String>(json['responseTag']),
      workUnits: serializer.fromJson<double>(json['workUnits']),
      amount: serializer.fromJson<double>(json['amount']),
      epoch: serializer.fromJson<String>(json['epoch']),
      expiresAt: serializer.fromJson<int>(json['expiresAt']),
      evidenceHash: serializer.fromJson<String?>(json['evidenceHash']),
      verifierSig: serializer.fromJson<String>(json['verifierSig']),
      proverSig: serializer.fromJson<String?>(json['proverSig']),
      spent: serializer.fromJson<bool>(json['spent']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'receiptId': serializer.toJson<String>(receiptId),
      'v': serializer.toJson<int>(v),
      'workType': serializer.toJson<String>(workType),
      'proverPubkey': serializer.toJson<String>(proverPubkey),
      'verifierPubkey': serializer.toJson<String>(verifierPubkey),
      'cid': serializer.toJson<String?>(cid),
      'chunkIndices': serializer.toJson<String>(chunkIndices),
      'challengeNonce': serializer.toJson<String>(challengeNonce),
      'responseTag': serializer.toJson<String>(responseTag),
      'workUnits': serializer.toJson<double>(workUnits),
      'amount': serializer.toJson<double>(amount),
      'epoch': serializer.toJson<String>(epoch),
      'expiresAt': serializer.toJson<int>(expiresAt),
      'evidenceHash': serializer.toJson<String?>(evidenceHash),
      'verifierSig': serializer.toJson<String>(verifierSig),
      'proverSig': serializer.toJson<String?>(proverSig),
      'spent': serializer.toJson<bool>(spent),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  WorkReceipt copyWith(
          {String? receiptId,
          int? v,
          String? workType,
          String? proverPubkey,
          String? verifierPubkey,
          Value<String?> cid = const Value.absent(),
          String? chunkIndices,
          String? challengeNonce,
          String? responseTag,
          double? workUnits,
          double? amount,
          String? epoch,
          int? expiresAt,
          Value<String?> evidenceHash = const Value.absent(),
          String? verifierSig,
          Value<String?> proverSig = const Value.absent(),
          bool? spent,
          DateTime? createdAt}) =>
      WorkReceipt(
        receiptId: receiptId ?? this.receiptId,
        v: v ?? this.v,
        workType: workType ?? this.workType,
        proverPubkey: proverPubkey ?? this.proverPubkey,
        verifierPubkey: verifierPubkey ?? this.verifierPubkey,
        cid: cid.present ? cid.value : this.cid,
        chunkIndices: chunkIndices ?? this.chunkIndices,
        challengeNonce: challengeNonce ?? this.challengeNonce,
        responseTag: responseTag ?? this.responseTag,
        workUnits: workUnits ?? this.workUnits,
        amount: amount ?? this.amount,
        epoch: epoch ?? this.epoch,
        expiresAt: expiresAt ?? this.expiresAt,
        evidenceHash:
            evidenceHash.present ? evidenceHash.value : this.evidenceHash,
        verifierSig: verifierSig ?? this.verifierSig,
        proverSig: proverSig.present ? proverSig.value : this.proverSig,
        spent: spent ?? this.spent,
        createdAt: createdAt ?? this.createdAt,
      );
  WorkReceipt copyWithCompanion(WorkReceiptsCompanion data) {
    return WorkReceipt(
      receiptId: data.receiptId.present ? data.receiptId.value : this.receiptId,
      v: data.v.present ? data.v.value : this.v,
      workType: data.workType.present ? data.workType.value : this.workType,
      proverPubkey: data.proverPubkey.present
          ? data.proverPubkey.value
          : this.proverPubkey,
      verifierPubkey: data.verifierPubkey.present
          ? data.verifierPubkey.value
          : this.verifierPubkey,
      cid: data.cid.present ? data.cid.value : this.cid,
      chunkIndices: data.chunkIndices.present
          ? data.chunkIndices.value
          : this.chunkIndices,
      challengeNonce: data.challengeNonce.present
          ? data.challengeNonce.value
          : this.challengeNonce,
      responseTag:
          data.responseTag.present ? data.responseTag.value : this.responseTag,
      workUnits: data.workUnits.present ? data.workUnits.value : this.workUnits,
      amount: data.amount.present ? data.amount.value : this.amount,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      evidenceHash: data.evidenceHash.present
          ? data.evidenceHash.value
          : this.evidenceHash,
      verifierSig:
          data.verifierSig.present ? data.verifierSig.value : this.verifierSig,
      proverSig: data.proverSig.present ? data.proverSig.value : this.proverSig,
      spent: data.spent.present ? data.spent.value : this.spent,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkReceipt(')
          ..write('receiptId: $receiptId, ')
          ..write('v: $v, ')
          ..write('workType: $workType, ')
          ..write('proverPubkey: $proverPubkey, ')
          ..write('verifierPubkey: $verifierPubkey, ')
          ..write('cid: $cid, ')
          ..write('chunkIndices: $chunkIndices, ')
          ..write('challengeNonce: $challengeNonce, ')
          ..write('responseTag: $responseTag, ')
          ..write('workUnits: $workUnits, ')
          ..write('amount: $amount, ')
          ..write('epoch: $epoch, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('verifierSig: $verifierSig, ')
          ..write('proverSig: $proverSig, ')
          ..write('spent: $spent, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      receiptId,
      v,
      workType,
      proverPubkey,
      verifierPubkey,
      cid,
      chunkIndices,
      challengeNonce,
      responseTag,
      workUnits,
      amount,
      epoch,
      expiresAt,
      evidenceHash,
      verifierSig,
      proverSig,
      spent,
      createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkReceipt &&
          other.receiptId == this.receiptId &&
          other.v == this.v &&
          other.workType == this.workType &&
          other.proverPubkey == this.proverPubkey &&
          other.verifierPubkey == this.verifierPubkey &&
          other.cid == this.cid &&
          other.chunkIndices == this.chunkIndices &&
          other.challengeNonce == this.challengeNonce &&
          other.responseTag == this.responseTag &&
          other.workUnits == this.workUnits &&
          other.amount == this.amount &&
          other.epoch == this.epoch &&
          other.expiresAt == this.expiresAt &&
          other.evidenceHash == this.evidenceHash &&
          other.verifierSig == this.verifierSig &&
          other.proverSig == this.proverSig &&
          other.spent == this.spent &&
          other.createdAt == this.createdAt);
}

class WorkReceiptsCompanion extends UpdateCompanion<WorkReceipt> {
  final Value<String> receiptId;
  final Value<int> v;
  final Value<String> workType;
  final Value<String> proverPubkey;
  final Value<String> verifierPubkey;
  final Value<String?> cid;
  final Value<String> chunkIndices;
  final Value<String> challengeNonce;
  final Value<String> responseTag;
  final Value<double> workUnits;
  final Value<double> amount;
  final Value<String> epoch;
  final Value<int> expiresAt;
  final Value<String?> evidenceHash;
  final Value<String> verifierSig;
  final Value<String?> proverSig;
  final Value<bool> spent;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const WorkReceiptsCompanion({
    this.receiptId = const Value.absent(),
    this.v = const Value.absent(),
    this.workType = const Value.absent(),
    this.proverPubkey = const Value.absent(),
    this.verifierPubkey = const Value.absent(),
    this.cid = const Value.absent(),
    this.chunkIndices = const Value.absent(),
    this.challengeNonce = const Value.absent(),
    this.responseTag = const Value.absent(),
    this.workUnits = const Value.absent(),
    this.amount = const Value.absent(),
    this.epoch = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.evidenceHash = const Value.absent(),
    this.verifierSig = const Value.absent(),
    this.proverSig = const Value.absent(),
    this.spent = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkReceiptsCompanion.insert({
    required String receiptId,
    this.v = const Value.absent(),
    required String workType,
    required String proverPubkey,
    required String verifierPubkey,
    this.cid = const Value.absent(),
    required String chunkIndices,
    required String challengeNonce,
    required String responseTag,
    required double workUnits,
    required double amount,
    required String epoch,
    required int expiresAt,
    this.evidenceHash = const Value.absent(),
    required String verifierSig,
    this.proverSig = const Value.absent(),
    this.spent = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : receiptId = Value(receiptId),
        workType = Value(workType),
        proverPubkey = Value(proverPubkey),
        verifierPubkey = Value(verifierPubkey),
        chunkIndices = Value(chunkIndices),
        challengeNonce = Value(challengeNonce),
        responseTag = Value(responseTag),
        workUnits = Value(workUnits),
        amount = Value(amount),
        epoch = Value(epoch),
        expiresAt = Value(expiresAt),
        verifierSig = Value(verifierSig),
        createdAt = Value(createdAt);
  static Insertable<WorkReceipt> custom({
    Expression<String>? receiptId,
    Expression<int>? v,
    Expression<String>? workType,
    Expression<String>? proverPubkey,
    Expression<String>? verifierPubkey,
    Expression<String>? cid,
    Expression<String>? chunkIndices,
    Expression<String>? challengeNonce,
    Expression<String>? responseTag,
    Expression<double>? workUnits,
    Expression<double>? amount,
    Expression<String>? epoch,
    Expression<int>? expiresAt,
    Expression<String>? evidenceHash,
    Expression<String>? verifierSig,
    Expression<String>? proverSig,
    Expression<bool>? spent,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (receiptId != null) 'receipt_id': receiptId,
      if (v != null) 'v': v,
      if (workType != null) 'work_type': workType,
      if (proverPubkey != null) 'prover_pubkey': proverPubkey,
      if (verifierPubkey != null) 'verifier_pubkey': verifierPubkey,
      if (cid != null) 'cid': cid,
      if (chunkIndices != null) 'chunk_indices': chunkIndices,
      if (challengeNonce != null) 'challenge_nonce': challengeNonce,
      if (responseTag != null) 'response_tag': responseTag,
      if (workUnits != null) 'work_units': workUnits,
      if (amount != null) 'amount': amount,
      if (epoch != null) 'epoch': epoch,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (evidenceHash != null) 'evidence_hash': evidenceHash,
      if (verifierSig != null) 'verifier_sig': verifierSig,
      if (proverSig != null) 'prover_sig': proverSig,
      if (spent != null) 'spent': spent,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkReceiptsCompanion copyWith(
      {Value<String>? receiptId,
      Value<int>? v,
      Value<String>? workType,
      Value<String>? proverPubkey,
      Value<String>? verifierPubkey,
      Value<String?>? cid,
      Value<String>? chunkIndices,
      Value<String>? challengeNonce,
      Value<String>? responseTag,
      Value<double>? workUnits,
      Value<double>? amount,
      Value<String>? epoch,
      Value<int>? expiresAt,
      Value<String?>? evidenceHash,
      Value<String>? verifierSig,
      Value<String?>? proverSig,
      Value<bool>? spent,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return WorkReceiptsCompanion(
      receiptId: receiptId ?? this.receiptId,
      v: v ?? this.v,
      workType: workType ?? this.workType,
      proverPubkey: proverPubkey ?? this.proverPubkey,
      verifierPubkey: verifierPubkey ?? this.verifierPubkey,
      cid: cid ?? this.cid,
      chunkIndices: chunkIndices ?? this.chunkIndices,
      challengeNonce: challengeNonce ?? this.challengeNonce,
      responseTag: responseTag ?? this.responseTag,
      workUnits: workUnits ?? this.workUnits,
      amount: amount ?? this.amount,
      epoch: epoch ?? this.epoch,
      expiresAt: expiresAt ?? this.expiresAt,
      evidenceHash: evidenceHash ?? this.evidenceHash,
      verifierSig: verifierSig ?? this.verifierSig,
      proverSig: proverSig ?? this.proverSig,
      spent: spent ?? this.spent,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (receiptId.present) {
      map['receipt_id'] = Variable<String>(receiptId.value);
    }
    if (v.present) {
      map['v'] = Variable<int>(v.value);
    }
    if (workType.present) {
      map['work_type'] = Variable<String>(workType.value);
    }
    if (proverPubkey.present) {
      map['prover_pubkey'] = Variable<String>(proverPubkey.value);
    }
    if (verifierPubkey.present) {
      map['verifier_pubkey'] = Variable<String>(verifierPubkey.value);
    }
    if (cid.present) {
      map['cid'] = Variable<String>(cid.value);
    }
    if (chunkIndices.present) {
      map['chunk_indices'] = Variable<String>(chunkIndices.value);
    }
    if (challengeNonce.present) {
      map['challenge_nonce'] = Variable<String>(challengeNonce.value);
    }
    if (responseTag.present) {
      map['response_tag'] = Variable<String>(responseTag.value);
    }
    if (workUnits.present) {
      map['work_units'] = Variable<double>(workUnits.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (epoch.present) {
      map['epoch'] = Variable<String>(epoch.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<int>(expiresAt.value);
    }
    if (evidenceHash.present) {
      map['evidence_hash'] = Variable<String>(evidenceHash.value);
    }
    if (verifierSig.present) {
      map['verifier_sig'] = Variable<String>(verifierSig.value);
    }
    if (proverSig.present) {
      map['prover_sig'] = Variable<String>(proverSig.value);
    }
    if (spent.present) {
      map['spent'] = Variable<bool>(spent.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkReceiptsCompanion(')
          ..write('receiptId: $receiptId, ')
          ..write('v: $v, ')
          ..write('workType: $workType, ')
          ..write('proverPubkey: $proverPubkey, ')
          ..write('verifierPubkey: $verifierPubkey, ')
          ..write('cid: $cid, ')
          ..write('chunkIndices: $chunkIndices, ')
          ..write('challengeNonce: $challengeNonce, ')
          ..write('responseTag: $responseTag, ')
          ..write('workUnits: $workUnits, ')
          ..write('amount: $amount, ')
          ..write('epoch: $epoch, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('evidenceHash: $evidenceHash, ')
          ..write('verifierSig: $verifierSig, ')
          ..write('proverSig: $proverSig, ')
          ..write('spent: $spent, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ClaimedBountiesTable extends ClaimedBounties
    with TableInfo<$ClaimedBountiesTable, ClaimedBounty> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ClaimedBountiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bountyIdMeta =
      const VerificationMeta('bountyId');
  @override
  late final GeneratedColumn<String> bountyId = GeneratedColumn<String>(
      'bounty_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cidMeta = const VerificationMeta('cid');
  @override
  late final GeneratedColumn<String> cid = GeneratedColumn<String>(
      'cid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _claimedAtMeta =
      const VerificationMeta('claimedAt');
  @override
  late final GeneratedColumn<int> claimedAt = GeneratedColumn<int>(
      'claimed_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [bountyId, cid, claimedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'claimed_bounties';
  @override
  VerificationContext validateIntegrity(Insertable<ClaimedBounty> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('bounty_id')) {
      context.handle(_bountyIdMeta,
          bountyId.isAcceptableOrUnknown(data['bounty_id']!, _bountyIdMeta));
    } else if (isInserting) {
      context.missing(_bountyIdMeta);
    }
    if (data.containsKey('cid')) {
      context.handle(
          _cidMeta, cid.isAcceptableOrUnknown(data['cid']!, _cidMeta));
    } else if (isInserting) {
      context.missing(_cidMeta);
    }
    if (data.containsKey('claimed_at')) {
      context.handle(_claimedAtMeta,
          claimedAt.isAcceptableOrUnknown(data['claimed_at']!, _claimedAtMeta));
    } else if (isInserting) {
      context.missing(_claimedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bountyId};
  @override
  ClaimedBounty map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ClaimedBounty(
      bountyId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}bounty_id'])!,
      cid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cid'])!,
      claimedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}claimed_at'])!,
    );
  }

  @override
  $ClaimedBountiesTable createAlias(String alias) {
    return $ClaimedBountiesTable(attachedDatabase, alias);
  }
}

class ClaimedBounty extends DataClass implements Insertable<ClaimedBounty> {
  final String bountyId;
  final String cid;
  final int claimedAt;
  const ClaimedBounty(
      {required this.bountyId, required this.cid, required this.claimedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['bounty_id'] = Variable<String>(bountyId);
    map['cid'] = Variable<String>(cid);
    map['claimed_at'] = Variable<int>(claimedAt);
    return map;
  }

  ClaimedBountiesCompanion toCompanion(bool nullToAbsent) {
    return ClaimedBountiesCompanion(
      bountyId: Value(bountyId),
      cid: Value(cid),
      claimedAt: Value(claimedAt),
    );
  }

  factory ClaimedBounty.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ClaimedBounty(
      bountyId: serializer.fromJson<String>(json['bountyId']),
      cid: serializer.fromJson<String>(json['cid']),
      claimedAt: serializer.fromJson<int>(json['claimedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bountyId': serializer.toJson<String>(bountyId),
      'cid': serializer.toJson<String>(cid),
      'claimedAt': serializer.toJson<int>(claimedAt),
    };
  }

  ClaimedBounty copyWith({String? bountyId, String? cid, int? claimedAt}) =>
      ClaimedBounty(
        bountyId: bountyId ?? this.bountyId,
        cid: cid ?? this.cid,
        claimedAt: claimedAt ?? this.claimedAt,
      );
  ClaimedBounty copyWithCompanion(ClaimedBountiesCompanion data) {
    return ClaimedBounty(
      bountyId: data.bountyId.present ? data.bountyId.value : this.bountyId,
      cid: data.cid.present ? data.cid.value : this.cid,
      claimedAt: data.claimedAt.present ? data.claimedAt.value : this.claimedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ClaimedBounty(')
          ..write('bountyId: $bountyId, ')
          ..write('cid: $cid, ')
          ..write('claimedAt: $claimedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bountyId, cid, claimedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ClaimedBounty &&
          other.bountyId == this.bountyId &&
          other.cid == this.cid &&
          other.claimedAt == this.claimedAt);
}

class ClaimedBountiesCompanion extends UpdateCompanion<ClaimedBounty> {
  final Value<String> bountyId;
  final Value<String> cid;
  final Value<int> claimedAt;
  final Value<int> rowid;
  const ClaimedBountiesCompanion({
    this.bountyId = const Value.absent(),
    this.cid = const Value.absent(),
    this.claimedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ClaimedBountiesCompanion.insert({
    required String bountyId,
    required String cid,
    required int claimedAt,
    this.rowid = const Value.absent(),
  })  : bountyId = Value(bountyId),
        cid = Value(cid),
        claimedAt = Value(claimedAt);
  static Insertable<ClaimedBounty> custom({
    Expression<String>? bountyId,
    Expression<String>? cid,
    Expression<int>? claimedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bountyId != null) 'bounty_id': bountyId,
      if (cid != null) 'cid': cid,
      if (claimedAt != null) 'claimed_at': claimedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ClaimedBountiesCompanion copyWith(
      {Value<String>? bountyId,
      Value<String>? cid,
      Value<int>? claimedAt,
      Value<int>? rowid}) {
    return ClaimedBountiesCompanion(
      bountyId: bountyId ?? this.bountyId,
      cid: cid ?? this.cid,
      claimedAt: claimedAt ?? this.claimedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bountyId.present) {
      map['bounty_id'] = Variable<String>(bountyId.value);
    }
    if (cid.present) {
      map['cid'] = Variable<String>(cid.value);
    }
    if (claimedAt.present) {
      map['claimed_at'] = Variable<int>(claimedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ClaimedBountiesCompanion(')
          ..write('bountyId: $bountyId, ')
          ..write('cid: $cid, ')
          ..write('claimedAt: $claimedAt, ')
          ..write('rowid: $rowid')
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
  late final $CreditTransactionsTable creditTransactions =
      $CreditTransactionsTable(this);
  late final $DailyMintedTable dailyMinted = $DailyMintedTable(this);
  late final $AwardedDoisTable awardedDois = $AwardedDoisTable(this);
  late final $WorkReceiptsTable workReceipts = $WorkReceiptsTable(this);
  late final $ClaimedBountiesTable claimedBounties =
      $ClaimedBountiesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        contentManifests,
        contentVersions,
        userProfiles,
        honorValidations,
        creditTransactions,
        dailyMinted,
        awardedDois,
        workReceipts,
        claimedBounties
      ];
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
              aliasName:
                  'content_manifests__id__content_versions__manifest_id');

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
                    e.readTable<$ContentManifestsTable, ContentManifest>(table),
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
  Value<String?> publisherPubkey,
  Value<String?> signature,
  Value<String?> flaggedReason,
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
  Value<String?> publisherPubkey,
  Value<String?> signature,
  Value<String?> flaggedReason,
});

final class $$ContentVersionsTableReferences extends BaseReferences<
    _$AppDatabase, $ContentVersionsTable, ContentVersion> {
  $$ContentVersionsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $ContentManifestsTable _manifestIdTable(_$AppDatabase db) =>
      db.contentManifests
          .createAlias('content_versions__manifest_id__content_manifests__id');

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

  ColumnFilters<String> get publisherPubkey => $composableBuilder(
      column: $table.publisherPubkey,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get signature => $composableBuilder(
      column: $table.signature, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get flaggedReason => $composableBuilder(
      column: $table.flaggedReason, builder: (column) => ColumnFilters(column));

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

  ColumnOrderings<String> get publisherPubkey => $composableBuilder(
      column: $table.publisherPubkey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get signature => $composableBuilder(
      column: $table.signature, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get flaggedReason => $composableBuilder(
      column: $table.flaggedReason,
      builder: (column) => ColumnOrderings(column));

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

  GeneratedColumn<String> get publisherPubkey => $composableBuilder(
      column: $table.publisherPubkey, builder: (column) => column);

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  GeneratedColumn<String> get flaggedReason => $composableBuilder(
      column: $table.flaggedReason, builder: (column) => column);

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
            Value<String?> publisherPubkey = const Value.absent(),
            Value<String?> signature = const Value.absent(),
            Value<String?> flaggedReason = const Value.absent(),
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
            publisherPubkey: publisherPubkey,
            signature: signature,
            flaggedReason: flaggedReason,
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
            Value<String?> publisherPubkey = const Value.absent(),
            Value<String?> signature = const Value.absent(),
            Value<String?> flaggedReason = const Value.absent(),
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
            publisherPubkey: publisherPubkey,
            signature: signature,
            flaggedReason: flaggedReason,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ContentVersionsTable, ContentVersion>(table),
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
              .map((e) => (
                    e.readTable<$UserProfilesTable, UserProfile>(table),
                    BaseReferences<_$AppDatabase, $UserProfilesTable,
                        UserProfile>(db, table, e)
                  ))
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
              .map((e) => (
                    e.readTable<$HonorValidationsTable, HonorValidation>(table),
                    BaseReferences<_$AppDatabase, $HonorValidationsTable,
                        HonorValidation>(db, table, e)
                  ))
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
typedef $$CreditTransactionsTableCreateCompanionBuilder
    = CreditTransactionsCompanion Function({
  required String id,
  required DateTime timestamp,
  required String type,
  required double amount,
  required String description,
  Value<String?> referenceId,
  required String hash,
  Value<bool> isAttested,
  Value<int> rowid,
});
typedef $$CreditTransactionsTableUpdateCompanionBuilder
    = CreditTransactionsCompanion Function({
  Value<String> id,
  Value<DateTime> timestamp,
  Value<String> type,
  Value<double> amount,
  Value<String> description,
  Value<String?> referenceId,
  Value<String> hash,
  Value<bool> isAttested,
  Value<int> rowid,
});

class $$CreditTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $CreditTransactionsTable> {
  $$CreditTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get hash => $composableBuilder(
      column: $table.hash, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isAttested => $composableBuilder(
      column: $table.isAttested, builder: (column) => ColumnFilters(column));
}

class $$CreditTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CreditTransactionsTable> {
  $$CreditTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get hash => $composableBuilder(
      column: $table.hash, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isAttested => $composableBuilder(
      column: $table.isAttested, builder: (column) => ColumnOrderings(column));
}

class $$CreditTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CreditTransactionsTable> {
  $$CreditTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => column);

  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<bool> get isAttested => $composableBuilder(
      column: $table.isAttested, builder: (column) => column);
}

class $$CreditTransactionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CreditTransactionsTable,
    CreditTransaction,
    $$CreditTransactionsTableFilterComposer,
    $$CreditTransactionsTableOrderingComposer,
    $$CreditTransactionsTableAnnotationComposer,
    $$CreditTransactionsTableCreateCompanionBuilder,
    $$CreditTransactionsTableUpdateCompanionBuilder,
    (
      CreditTransaction,
      BaseReferences<_$AppDatabase, $CreditTransactionsTable, CreditTransaction>
    ),
    CreditTransaction,
    PrefetchHooks Function()> {
  $$CreditTransactionsTableTableManager(
      _$AppDatabase db, $CreditTransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CreditTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CreditTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CreditTransactionsTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String?> referenceId = const Value.absent(),
            Value<String> hash = const Value.absent(),
            Value<bool> isAttested = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CreditTransactionsCompanion(
            id: id,
            timestamp: timestamp,
            type: type,
            amount: amount,
            description: description,
            referenceId: referenceId,
            hash: hash,
            isAttested: isAttested,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required DateTime timestamp,
            required String type,
            required double amount,
            required String description,
            Value<String?> referenceId = const Value.absent(),
            required String hash,
            Value<bool> isAttested = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CreditTransactionsCompanion.insert(
            id: id,
            timestamp: timestamp,
            type: type,
            amount: amount,
            description: description,
            referenceId: referenceId,
            hash: hash,
            isAttested: isAttested,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CreditTransactionsTable, CreditTransaction>(
                        table),
                    BaseReferences<_$AppDatabase, $CreditTransactionsTable,
                        CreditTransaction>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CreditTransactionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CreditTransactionsTable,
    CreditTransaction,
    $$CreditTransactionsTableFilterComposer,
    $$CreditTransactionsTableOrderingComposer,
    $$CreditTransactionsTableAnnotationComposer,
    $$CreditTransactionsTableCreateCompanionBuilder,
    $$CreditTransactionsTableUpdateCompanionBuilder,
    (
      CreditTransaction,
      BaseReferences<_$AppDatabase, $CreditTransactionsTable, CreditTransaction>
    ),
    CreditTransaction,
    PrefetchHooks Function()>;
typedef $$DailyMintedTableCreateCompanionBuilder = DailyMintedCompanion
    Function({
  required String dayKey,
  required String creditType,
  required double amount,
  Value<int> rowid,
});
typedef $$DailyMintedTableUpdateCompanionBuilder = DailyMintedCompanion
    Function({
  Value<String> dayKey,
  Value<String> creditType,
  Value<double> amount,
  Value<int> rowid,
});

class $$DailyMintedTableFilterComposer
    extends Composer<_$AppDatabase, $DailyMintedTable> {
  $$DailyMintedTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get dayKey => $composableBuilder(
      column: $table.dayKey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get creditType => $composableBuilder(
      column: $table.creditType, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));
}

class $$DailyMintedTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyMintedTable> {
  $$DailyMintedTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get dayKey => $composableBuilder(
      column: $table.dayKey, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get creditType => $composableBuilder(
      column: $table.creditType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));
}

class $$DailyMintedTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyMintedTable> {
  $$DailyMintedTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get dayKey =>
      $composableBuilder(column: $table.dayKey, builder: (column) => column);

  GeneratedColumn<String> get creditType => $composableBuilder(
      column: $table.creditType, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);
}

class $$DailyMintedTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DailyMintedTable,
    DailyMintedData,
    $$DailyMintedTableFilterComposer,
    $$DailyMintedTableOrderingComposer,
    $$DailyMintedTableAnnotationComposer,
    $$DailyMintedTableCreateCompanionBuilder,
    $$DailyMintedTableUpdateCompanionBuilder,
    (
      DailyMintedData,
      BaseReferences<_$AppDatabase, $DailyMintedTable, DailyMintedData>
    ),
    DailyMintedData,
    PrefetchHooks Function()> {
  $$DailyMintedTableTableManager(_$AppDatabase db, $DailyMintedTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyMintedTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyMintedTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyMintedTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> dayKey = const Value.absent(),
            Value<String> creditType = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DailyMintedCompanion(
            dayKey: dayKey,
            creditType: creditType,
            amount: amount,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String dayKey,
            required String creditType,
            required double amount,
            Value<int> rowid = const Value.absent(),
          }) =>
              DailyMintedCompanion.insert(
            dayKey: dayKey,
            creditType: creditType,
            amount: amount,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$DailyMintedTable, DailyMintedData>(table),
                    BaseReferences<_$AppDatabase, $DailyMintedTable,
                        DailyMintedData>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DailyMintedTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DailyMintedTable,
    DailyMintedData,
    $$DailyMintedTableFilterComposer,
    $$DailyMintedTableOrderingComposer,
    $$DailyMintedTableAnnotationComposer,
    $$DailyMintedTableCreateCompanionBuilder,
    $$DailyMintedTableUpdateCompanionBuilder,
    (
      DailyMintedData,
      BaseReferences<_$AppDatabase, $DailyMintedTable, DailyMintedData>
    ),
    DailyMintedData,
    PrefetchHooks Function()>;
typedef $$AwardedDoisTableCreateCompanionBuilder = AwardedDoisCompanion
    Function({
  required String doi,
  required DateTime awardedAt,
  Value<String?> cid,
  Value<int> rowid,
});
typedef $$AwardedDoisTableUpdateCompanionBuilder = AwardedDoisCompanion
    Function({
  Value<String> doi,
  Value<DateTime> awardedAt,
  Value<String?> cid,
  Value<int> rowid,
});

class $$AwardedDoisTableFilterComposer
    extends Composer<_$AppDatabase, $AwardedDoisTable> {
  $$AwardedDoisTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get doi => $composableBuilder(
      column: $table.doi, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get awardedAt => $composableBuilder(
      column: $table.awardedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnFilters(column));
}

class $$AwardedDoisTableOrderingComposer
    extends Composer<_$AppDatabase, $AwardedDoisTable> {
  $$AwardedDoisTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get doi => $composableBuilder(
      column: $table.doi, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get awardedAt => $composableBuilder(
      column: $table.awardedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnOrderings(column));
}

class $$AwardedDoisTableAnnotationComposer
    extends Composer<_$AppDatabase, $AwardedDoisTable> {
  $$AwardedDoisTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get doi =>
      $composableBuilder(column: $table.doi, builder: (column) => column);

  GeneratedColumn<DateTime> get awardedAt =>
      $composableBuilder(column: $table.awardedAt, builder: (column) => column);

  GeneratedColumn<String> get cid =>
      $composableBuilder(column: $table.cid, builder: (column) => column);
}

class $$AwardedDoisTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AwardedDoisTable,
    AwardedDoi,
    $$AwardedDoisTableFilterComposer,
    $$AwardedDoisTableOrderingComposer,
    $$AwardedDoisTableAnnotationComposer,
    $$AwardedDoisTableCreateCompanionBuilder,
    $$AwardedDoisTableUpdateCompanionBuilder,
    (AwardedDoi, BaseReferences<_$AppDatabase, $AwardedDoisTable, AwardedDoi>),
    AwardedDoi,
    PrefetchHooks Function()> {
  $$AwardedDoisTableTableManager(_$AppDatabase db, $AwardedDoisTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AwardedDoisTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AwardedDoisTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AwardedDoisTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> doi = const Value.absent(),
            Value<DateTime> awardedAt = const Value.absent(),
            Value<String?> cid = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AwardedDoisCompanion(
            doi: doi,
            awardedAt: awardedAt,
            cid: cid,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String doi,
            required DateTime awardedAt,
            Value<String?> cid = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AwardedDoisCompanion.insert(
            doi: doi,
            awardedAt: awardedAt,
            cid: cid,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$AwardedDoisTable, AwardedDoi>(table),
                    BaseReferences<_$AppDatabase, $AwardedDoisTable,
                        AwardedDoi>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AwardedDoisTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AwardedDoisTable,
    AwardedDoi,
    $$AwardedDoisTableFilterComposer,
    $$AwardedDoisTableOrderingComposer,
    $$AwardedDoisTableAnnotationComposer,
    $$AwardedDoisTableCreateCompanionBuilder,
    $$AwardedDoisTableUpdateCompanionBuilder,
    (AwardedDoi, BaseReferences<_$AppDatabase, $AwardedDoisTable, AwardedDoi>),
    AwardedDoi,
    PrefetchHooks Function()>;
typedef $$WorkReceiptsTableCreateCompanionBuilder = WorkReceiptsCompanion
    Function({
  required String receiptId,
  Value<int> v,
  required String workType,
  required String proverPubkey,
  required String verifierPubkey,
  Value<String?> cid,
  required String chunkIndices,
  required String challengeNonce,
  required String responseTag,
  required double workUnits,
  required double amount,
  required String epoch,
  required int expiresAt,
  Value<String?> evidenceHash,
  required String verifierSig,
  Value<String?> proverSig,
  Value<bool> spent,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$WorkReceiptsTableUpdateCompanionBuilder = WorkReceiptsCompanion
    Function({
  Value<String> receiptId,
  Value<int> v,
  Value<String> workType,
  Value<String> proverPubkey,
  Value<String> verifierPubkey,
  Value<String?> cid,
  Value<String> chunkIndices,
  Value<String> challengeNonce,
  Value<String> responseTag,
  Value<double> workUnits,
  Value<double> amount,
  Value<String> epoch,
  Value<int> expiresAt,
  Value<String?> evidenceHash,
  Value<String> verifierSig,
  Value<String?> proverSig,
  Value<bool> spent,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$WorkReceiptsTableFilterComposer
    extends Composer<_$AppDatabase, $WorkReceiptsTable> {
  $$WorkReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get receiptId => $composableBuilder(
      column: $table.receiptId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get v => $composableBuilder(
      column: $table.v, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get workType => $composableBuilder(
      column: $table.workType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get proverPubkey => $composableBuilder(
      column: $table.proverPubkey, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get verifierPubkey => $composableBuilder(
      column: $table.verifierPubkey,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get chunkIndices => $composableBuilder(
      column: $table.chunkIndices, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get challengeNonce => $composableBuilder(
      column: $table.challengeNonce,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get responseTag => $composableBuilder(
      column: $table.responseTag, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get workUnits => $composableBuilder(
      column: $table.workUnits, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get epoch => $composableBuilder(
      column: $table.epoch, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get evidenceHash => $composableBuilder(
      column: $table.evidenceHash, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get verifierSig => $composableBuilder(
      column: $table.verifierSig, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get proverSig => $composableBuilder(
      column: $table.proverSig, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get spent => $composableBuilder(
      column: $table.spent, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$WorkReceiptsTableOrderingComposer
    extends Composer<_$AppDatabase, $WorkReceiptsTable> {
  $$WorkReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get receiptId => $composableBuilder(
      column: $table.receiptId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get v => $composableBuilder(
      column: $table.v, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get workType => $composableBuilder(
      column: $table.workType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get proverPubkey => $composableBuilder(
      column: $table.proverPubkey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get verifierPubkey => $composableBuilder(
      column: $table.verifierPubkey,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get chunkIndices => $composableBuilder(
      column: $table.chunkIndices,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get challengeNonce => $composableBuilder(
      column: $table.challengeNonce,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get responseTag => $composableBuilder(
      column: $table.responseTag, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get workUnits => $composableBuilder(
      column: $table.workUnits, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get epoch => $composableBuilder(
      column: $table.epoch, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get evidenceHash => $composableBuilder(
      column: $table.evidenceHash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get verifierSig => $composableBuilder(
      column: $table.verifierSig, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get proverSig => $composableBuilder(
      column: $table.proverSig, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get spent => $composableBuilder(
      column: $table.spent, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$WorkReceiptsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WorkReceiptsTable> {
  $$WorkReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get receiptId =>
      $composableBuilder(column: $table.receiptId, builder: (column) => column);

  GeneratedColumn<int> get v =>
      $composableBuilder(column: $table.v, builder: (column) => column);

  GeneratedColumn<String> get workType =>
      $composableBuilder(column: $table.workType, builder: (column) => column);

  GeneratedColumn<String> get proverPubkey => $composableBuilder(
      column: $table.proverPubkey, builder: (column) => column);

  GeneratedColumn<String> get verifierPubkey => $composableBuilder(
      column: $table.verifierPubkey, builder: (column) => column);

  GeneratedColumn<String> get cid =>
      $composableBuilder(column: $table.cid, builder: (column) => column);

  GeneratedColumn<String> get chunkIndices => $composableBuilder(
      column: $table.chunkIndices, builder: (column) => column);

  GeneratedColumn<String> get challengeNonce => $composableBuilder(
      column: $table.challengeNonce, builder: (column) => column);

  GeneratedColumn<String> get responseTag => $composableBuilder(
      column: $table.responseTag, builder: (column) => column);

  GeneratedColumn<double> get workUnits =>
      $composableBuilder(column: $table.workUnits, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);

  GeneratedColumn<int> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<String> get evidenceHash => $composableBuilder(
      column: $table.evidenceHash, builder: (column) => column);

  GeneratedColumn<String> get verifierSig => $composableBuilder(
      column: $table.verifierSig, builder: (column) => column);

  GeneratedColumn<String> get proverSig =>
      $composableBuilder(column: $table.proverSig, builder: (column) => column);

  GeneratedColumn<bool> get spent =>
      $composableBuilder(column: $table.spent, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$WorkReceiptsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $WorkReceiptsTable,
    WorkReceipt,
    $$WorkReceiptsTableFilterComposer,
    $$WorkReceiptsTableOrderingComposer,
    $$WorkReceiptsTableAnnotationComposer,
    $$WorkReceiptsTableCreateCompanionBuilder,
    $$WorkReceiptsTableUpdateCompanionBuilder,
    (
      WorkReceipt,
      BaseReferences<_$AppDatabase, $WorkReceiptsTable, WorkReceipt>
    ),
    WorkReceipt,
    PrefetchHooks Function()> {
  $$WorkReceiptsTableTableManager(_$AppDatabase db, $WorkReceiptsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> receiptId = const Value.absent(),
            Value<int> v = const Value.absent(),
            Value<String> workType = const Value.absent(),
            Value<String> proverPubkey = const Value.absent(),
            Value<String> verifierPubkey = const Value.absent(),
            Value<String?> cid = const Value.absent(),
            Value<String> chunkIndices = const Value.absent(),
            Value<String> challengeNonce = const Value.absent(),
            Value<String> responseTag = const Value.absent(),
            Value<double> workUnits = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> epoch = const Value.absent(),
            Value<int> expiresAt = const Value.absent(),
            Value<String?> evidenceHash = const Value.absent(),
            Value<String> verifierSig = const Value.absent(),
            Value<String?> proverSig = const Value.absent(),
            Value<bool> spent = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              WorkReceiptsCompanion(
            receiptId: receiptId,
            v: v,
            workType: workType,
            proverPubkey: proverPubkey,
            verifierPubkey: verifierPubkey,
            cid: cid,
            chunkIndices: chunkIndices,
            challengeNonce: challengeNonce,
            responseTag: responseTag,
            workUnits: workUnits,
            amount: amount,
            epoch: epoch,
            expiresAt: expiresAt,
            evidenceHash: evidenceHash,
            verifierSig: verifierSig,
            proverSig: proverSig,
            spent: spent,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String receiptId,
            Value<int> v = const Value.absent(),
            required String workType,
            required String proverPubkey,
            required String verifierPubkey,
            Value<String?> cid = const Value.absent(),
            required String chunkIndices,
            required String challengeNonce,
            required String responseTag,
            required double workUnits,
            required double amount,
            required String epoch,
            required int expiresAt,
            Value<String?> evidenceHash = const Value.absent(),
            required String verifierSig,
            Value<String?> proverSig = const Value.absent(),
            Value<bool> spent = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              WorkReceiptsCompanion.insert(
            receiptId: receiptId,
            v: v,
            workType: workType,
            proverPubkey: proverPubkey,
            verifierPubkey: verifierPubkey,
            cid: cid,
            chunkIndices: chunkIndices,
            challengeNonce: challengeNonce,
            responseTag: responseTag,
            workUnits: workUnits,
            amount: amount,
            epoch: epoch,
            expiresAt: expiresAt,
            evidenceHash: evidenceHash,
            verifierSig: verifierSig,
            proverSig: proverSig,
            spent: spent,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$WorkReceiptsTable, WorkReceipt>(table),
                    BaseReferences<_$AppDatabase, $WorkReceiptsTable,
                        WorkReceipt>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$WorkReceiptsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $WorkReceiptsTable,
    WorkReceipt,
    $$WorkReceiptsTableFilterComposer,
    $$WorkReceiptsTableOrderingComposer,
    $$WorkReceiptsTableAnnotationComposer,
    $$WorkReceiptsTableCreateCompanionBuilder,
    $$WorkReceiptsTableUpdateCompanionBuilder,
    (
      WorkReceipt,
      BaseReferences<_$AppDatabase, $WorkReceiptsTable, WorkReceipt>
    ),
    WorkReceipt,
    PrefetchHooks Function()>;
typedef $$ClaimedBountiesTableCreateCompanionBuilder = ClaimedBountiesCompanion
    Function({
  required String bountyId,
  required String cid,
  required int claimedAt,
  Value<int> rowid,
});
typedef $$ClaimedBountiesTableUpdateCompanionBuilder = ClaimedBountiesCompanion
    Function({
  Value<String> bountyId,
  Value<String> cid,
  Value<int> claimedAt,
  Value<int> rowid,
});

class $$ClaimedBountiesTableFilterComposer
    extends Composer<_$AppDatabase, $ClaimedBountiesTable> {
  $$ClaimedBountiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bountyId => $composableBuilder(
      column: $table.bountyId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get claimedAt => $composableBuilder(
      column: $table.claimedAt, builder: (column) => ColumnFilters(column));
}

class $$ClaimedBountiesTableOrderingComposer
    extends Composer<_$AppDatabase, $ClaimedBountiesTable> {
  $$ClaimedBountiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bountyId => $composableBuilder(
      column: $table.bountyId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cid => $composableBuilder(
      column: $table.cid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get claimedAt => $composableBuilder(
      column: $table.claimedAt, builder: (column) => ColumnOrderings(column));
}

class $$ClaimedBountiesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ClaimedBountiesTable> {
  $$ClaimedBountiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bountyId =>
      $composableBuilder(column: $table.bountyId, builder: (column) => column);

  GeneratedColumn<String> get cid =>
      $composableBuilder(column: $table.cid, builder: (column) => column);

  GeneratedColumn<int> get claimedAt =>
      $composableBuilder(column: $table.claimedAt, builder: (column) => column);
}

class $$ClaimedBountiesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ClaimedBountiesTable,
    ClaimedBounty,
    $$ClaimedBountiesTableFilterComposer,
    $$ClaimedBountiesTableOrderingComposer,
    $$ClaimedBountiesTableAnnotationComposer,
    $$ClaimedBountiesTableCreateCompanionBuilder,
    $$ClaimedBountiesTableUpdateCompanionBuilder,
    (
      ClaimedBounty,
      BaseReferences<_$AppDatabase, $ClaimedBountiesTable, ClaimedBounty>
    ),
    ClaimedBounty,
    PrefetchHooks Function()> {
  $$ClaimedBountiesTableTableManager(
      _$AppDatabase db, $ClaimedBountiesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ClaimedBountiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ClaimedBountiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ClaimedBountiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> bountyId = const Value.absent(),
            Value<String> cid = const Value.absent(),
            Value<int> claimedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ClaimedBountiesCompanion(
            bountyId: bountyId,
            cid: cid,
            claimedAt: claimedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String bountyId,
            required String cid,
            required int claimedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ClaimedBountiesCompanion.insert(
            bountyId: bountyId,
            cid: cid,
            claimedAt: claimedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ClaimedBountiesTable, ClaimedBounty>(table),
                    BaseReferences<_$AppDatabase, $ClaimedBountiesTable,
                        ClaimedBounty>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ClaimedBountiesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ClaimedBountiesTable,
    ClaimedBounty,
    $$ClaimedBountiesTableFilterComposer,
    $$ClaimedBountiesTableOrderingComposer,
    $$ClaimedBountiesTableAnnotationComposer,
    $$ClaimedBountiesTableCreateCompanionBuilder,
    $$ClaimedBountiesTableUpdateCompanionBuilder,
    (
      ClaimedBounty,
      BaseReferences<_$AppDatabase, $ClaimedBountiesTable, ClaimedBounty>
    ),
    ClaimedBounty,
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
  $$CreditTransactionsTableTableManager get creditTransactions =>
      $$CreditTransactionsTableTableManager(_db, _db.creditTransactions);
  $$DailyMintedTableTableManager get dailyMinted =>
      $$DailyMintedTableTableManager(_db, _db.dailyMinted);
  $$AwardedDoisTableTableManager get awardedDois =>
      $$AwardedDoisTableTableManager(_db, _db.awardedDois);
  $$WorkReceiptsTableTableManager get workReceipts =>
      $$WorkReceiptsTableTableManager(_db, _db.workReceipts);
  $$ClaimedBountiesTableTableManager get claimedBounties =>
      $$ClaimedBountiesTableTableManager(_db, _db.claimedBounties);
}
