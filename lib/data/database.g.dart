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
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _uuidMeta = const VerificationMeta('uuid');
  @override
  late final GeneratedColumn<String> uuid = GeneratedColumn<String>(
    'uuid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('other'),
  );
  static const VerificationMeta _metadataMeta = const VerificationMeta(
    'metadata',
  );
  @override
  late final GeneratedColumn<String> metadata = GeneratedColumn<String>(
    'metadata',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isEncryptedMeta = const VerificationMeta(
    'isEncrypted',
  );
  @override
  late final GeneratedColumn<bool> isEncrypted = GeneratedColumn<bool>(
    'is_encrypted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_encrypted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _encryptionKeyMeta = const VerificationMeta(
    'encryptionKey',
  );
  @override
  late final GeneratedColumn<String> encryptionKey = GeneratedColumn<String>(
    'encryption_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _encryptionKeyHashMeta = const VerificationMeta(
    'encryptionKeyHash',
  );
  @override
  late final GeneratedColumn<String> encryptionKeyHash =
      GeneratedColumn<String>(
        'encryption_key_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastUpdatedMeta = const VerificationMeta(
    'lastUpdated',
  );
  @override
  late final GeneratedColumn<DateTime> lastUpdated = GeneratedColumn<DateTime>(
    'last_updated',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _parentCidMeta = const VerificationMeta(
    'parentCid',
  );
  @override
  late final GeneratedColumn<String> parentCid = GeneratedColumn<String>(
    'parent_cid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _siblingCidsMeta = const VerificationMeta(
    'siblingCids',
  );
  @override
  late final GeneratedColumn<String> siblingCids = GeneratedColumn<String>(
    'sibling_cids',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rootCidMeta = const VerificationMeta(
    'rootCid',
  );
  @override
  late final GeneratedColumn<String> rootCid = GeneratedColumn<String>(
    'root_cid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publisherKeyMeta = const VerificationMeta(
    'publisherKey',
  );
  @override
  late final GeneratedColumn<String> publisherKey = GeneratedColumn<String>(
    'publisher_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    uuid,
    title,
    description,
    author,
    tags,
    category,
    metadata,
    isEncrypted,
    encryptionKey,
    encryptionKeyHash,
    lastUpdated,
    version,
    parentCid,
    siblingCids,
    rootCid,
    publisherKey,
    signature,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_manifests';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContentManifest> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('uuid')) {
      context.handle(
        _uuidMeta,
        uuid.isAcceptableOrUnknown(data['uuid']!, _uuidMeta),
      );
    } else if (isInserting) {
      context.missing(_uuidMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('metadata')) {
      context.handle(
        _metadataMeta,
        metadata.isAcceptableOrUnknown(data['metadata']!, _metadataMeta),
      );
    }
    if (data.containsKey('is_encrypted')) {
      context.handle(
        _isEncryptedMeta,
        isEncrypted.isAcceptableOrUnknown(
          data['is_encrypted']!,
          _isEncryptedMeta,
        ),
      );
    }
    if (data.containsKey('encryption_key')) {
      context.handle(
        _encryptionKeyMeta,
        encryptionKey.isAcceptableOrUnknown(
          data['encryption_key']!,
          _encryptionKeyMeta,
        ),
      );
    }
    if (data.containsKey('encryption_key_hash')) {
      context.handle(
        _encryptionKeyHashMeta,
        encryptionKeyHash.isAcceptableOrUnknown(
          data['encryption_key_hash']!,
          _encryptionKeyHashMeta,
        ),
      );
    }
    if (data.containsKey('last_updated')) {
      context.handle(
        _lastUpdatedMeta,
        lastUpdated.isAcceptableOrUnknown(
          data['last_updated']!,
          _lastUpdatedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUpdatedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('parent_cid')) {
      context.handle(
        _parentCidMeta,
        parentCid.isAcceptableOrUnknown(data['parent_cid']!, _parentCidMeta),
      );
    }
    if (data.containsKey('sibling_cids')) {
      context.handle(
        _siblingCidsMeta,
        siblingCids.isAcceptableOrUnknown(
          data['sibling_cids']!,
          _siblingCidsMeta,
        ),
      );
    }
    if (data.containsKey('root_cid')) {
      context.handle(
        _rootCidMeta,
        rootCid.isAcceptableOrUnknown(data['root_cid']!, _rootCidMeta),
      );
    }
    if (data.containsKey('publisher_key')) {
      context.handle(
        _publisherKeyMeta,
        publisherKey.isAcceptableOrUnknown(
          data['publisher_key']!,
          _publisherKeyMeta,
        ),
      );
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContentManifest map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentManifest(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      uuid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uuid'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      ),
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      ),
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      metadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metadata'],
      ),
      isEncrypted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_encrypted'],
      )!,
      encryptionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encryption_key'],
      ),
      encryptionKeyHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encryption_key_hash'],
      ),
      lastUpdated: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_updated'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      parentCid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_cid'],
      ),
      siblingCids: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sibling_cids'],
      ),
      rootCid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}root_cid'],
      ),
      publisherKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher_key'],
      ),
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      ),
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
  final String? description;
  final String? author;
  final String? tags;
  final String category;
  final String? metadata;
  final bool isEncrypted;
  final String? encryptionKey;
  final String? encryptionKeyHash;
  final DateTime lastUpdated;
  final int version;
  final String? parentCid;
  final String? siblingCids;
  final String? rootCid;
  final String? publisherKey;
  final String? signature;
  const ContentManifest({
    required this.id,
    required this.uuid,
    required this.title,
    this.description,
    this.author,
    this.tags,
    required this.category,
    this.metadata,
    required this.isEncrypted,
    this.encryptionKey,
    this.encryptionKeyHash,
    required this.lastUpdated,
    required this.version,
    this.parentCid,
    this.siblingCids,
    this.rootCid,
    this.publisherKey,
    this.signature,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['uuid'] = Variable<String>(uuid);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || tags != null) {
      map['tags'] = Variable<String>(tags);
    }
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || metadata != null) {
      map['metadata'] = Variable<String>(metadata);
    }
    map['is_encrypted'] = Variable<bool>(isEncrypted);
    if (!nullToAbsent || encryptionKey != null) {
      map['encryption_key'] = Variable<String>(encryptionKey);
    }
    if (!nullToAbsent || encryptionKeyHash != null) {
      map['encryption_key_hash'] = Variable<String>(encryptionKeyHash);
    }
    map['last_updated'] = Variable<DateTime>(lastUpdated);
    map['version'] = Variable<int>(version);
    if (!nullToAbsent || parentCid != null) {
      map['parent_cid'] = Variable<String>(parentCid);
    }
    if (!nullToAbsent || siblingCids != null) {
      map['sibling_cids'] = Variable<String>(siblingCids);
    }
    if (!nullToAbsent || rootCid != null) {
      map['root_cid'] = Variable<String>(rootCid);
    }
    if (!nullToAbsent || publisherKey != null) {
      map['publisher_key'] = Variable<String>(publisherKey);
    }
    if (!nullToAbsent || signature != null) {
      map['signature'] = Variable<String>(signature);
    }
    return map;
  }

  ContentManifestsCompanion toCompanion(bool nullToAbsent) {
    return ContentManifestsCompanion(
      id: Value(id),
      uuid: Value(uuid),
      title: Value(title),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      author: author == null && nullToAbsent
          ? const Value.absent()
          : Value(author),
      tags: tags == null && nullToAbsent ? const Value.absent() : Value(tags),
      category: Value(category),
      metadata: metadata == null && nullToAbsent
          ? const Value.absent()
          : Value(metadata),
      isEncrypted: Value(isEncrypted),
      encryptionKey: encryptionKey == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptionKey),
      encryptionKeyHash: encryptionKeyHash == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptionKeyHash),
      lastUpdated: Value(lastUpdated),
      version: Value(version),
      parentCid: parentCid == null && nullToAbsent
          ? const Value.absent()
          : Value(parentCid),
      siblingCids: siblingCids == null && nullToAbsent
          ? const Value.absent()
          : Value(siblingCids),
      rootCid: rootCid == null && nullToAbsent
          ? const Value.absent()
          : Value(rootCid),
      publisherKey: publisherKey == null && nullToAbsent
          ? const Value.absent()
          : Value(publisherKey),
      signature: signature == null && nullToAbsent
          ? const Value.absent()
          : Value(signature),
    );
  }

  factory ContentManifest.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentManifest(
      id: serializer.fromJson<int>(json['id']),
      uuid: serializer.fromJson<String>(json['uuid']),
      title: serializer.fromJson<String>(json['title']),
      description: serializer.fromJson<String?>(json['description']),
      author: serializer.fromJson<String?>(json['author']),
      tags: serializer.fromJson<String?>(json['tags']),
      category: serializer.fromJson<String>(json['category']),
      metadata: serializer.fromJson<String?>(json['metadata']),
      isEncrypted: serializer.fromJson<bool>(json['isEncrypted']),
      encryptionKey: serializer.fromJson<String?>(json['encryptionKey']),
      encryptionKeyHash: serializer.fromJson<String?>(
        json['encryptionKeyHash'],
      ),
      lastUpdated: serializer.fromJson<DateTime>(json['lastUpdated']),
      version: serializer.fromJson<int>(json['version']),
      parentCid: serializer.fromJson<String?>(json['parentCid']),
      siblingCids: serializer.fromJson<String?>(json['siblingCids']),
      rootCid: serializer.fromJson<String?>(json['rootCid']),
      publisherKey: serializer.fromJson<String?>(json['publisherKey']),
      signature: serializer.fromJson<String?>(json['signature']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'uuid': serializer.toJson<String>(uuid),
      'title': serializer.toJson<String>(title),
      'description': serializer.toJson<String?>(description),
      'author': serializer.toJson<String?>(author),
      'tags': serializer.toJson<String?>(tags),
      'category': serializer.toJson<String>(category),
      'metadata': serializer.toJson<String?>(metadata),
      'isEncrypted': serializer.toJson<bool>(isEncrypted),
      'encryptionKey': serializer.toJson<String?>(encryptionKey),
      'encryptionKeyHash': serializer.toJson<String?>(encryptionKeyHash),
      'lastUpdated': serializer.toJson<DateTime>(lastUpdated),
      'version': serializer.toJson<int>(version),
      'parentCid': serializer.toJson<String?>(parentCid),
      'siblingCids': serializer.toJson<String?>(siblingCids),
      'rootCid': serializer.toJson<String?>(rootCid),
      'publisherKey': serializer.toJson<String?>(publisherKey),
      'signature': serializer.toJson<String?>(signature),
    };
  }

  ContentManifest copyWith({
    int? id,
    String? uuid,
    String? title,
    Value<String?> description = const Value.absent(),
    Value<String?> author = const Value.absent(),
    Value<String?> tags = const Value.absent(),
    String? category,
    Value<String?> metadata = const Value.absent(),
    bool? isEncrypted,
    Value<String?> encryptionKey = const Value.absent(),
    Value<String?> encryptionKeyHash = const Value.absent(),
    DateTime? lastUpdated,
    int? version,
    Value<String?> parentCid = const Value.absent(),
    Value<String?> siblingCids = const Value.absent(),
    Value<String?> rootCid = const Value.absent(),
    Value<String?> publisherKey = const Value.absent(),
    Value<String?> signature = const Value.absent(),
  }) => ContentManifest(
    id: id ?? this.id,
    uuid: uuid ?? this.uuid,
    title: title ?? this.title,
    description: description.present ? description.value : this.description,
    author: author.present ? author.value : this.author,
    tags: tags.present ? tags.value : this.tags,
    category: category ?? this.category,
    metadata: metadata.present ? metadata.value : this.metadata,
    isEncrypted: isEncrypted ?? this.isEncrypted,
    encryptionKey: encryptionKey.present
        ? encryptionKey.value
        : this.encryptionKey,
    encryptionKeyHash: encryptionKeyHash.present
        ? encryptionKeyHash.value
        : this.encryptionKeyHash,
    lastUpdated: lastUpdated ?? this.lastUpdated,
    version: version ?? this.version,
    parentCid: parentCid.present ? parentCid.value : this.parentCid,
    siblingCids: siblingCids.present ? siblingCids.value : this.siblingCids,
    rootCid: rootCid.present ? rootCid.value : this.rootCid,
    publisherKey: publisherKey.present ? publisherKey.value : this.publisherKey,
    signature: signature.present ? signature.value : this.signature,
  );
  ContentManifest copyWithCompanion(ContentManifestsCompanion data) {
    return ContentManifest(
      id: data.id.present ? data.id.value : this.id,
      uuid: data.uuid.present ? data.uuid.value : this.uuid,
      title: data.title.present ? data.title.value : this.title,
      description: data.description.present
          ? data.description.value
          : this.description,
      author: data.author.present ? data.author.value : this.author,
      tags: data.tags.present ? data.tags.value : this.tags,
      category: data.category.present ? data.category.value : this.category,
      metadata: data.metadata.present ? data.metadata.value : this.metadata,
      isEncrypted: data.isEncrypted.present
          ? data.isEncrypted.value
          : this.isEncrypted,
      encryptionKey: data.encryptionKey.present
          ? data.encryptionKey.value
          : this.encryptionKey,
      encryptionKeyHash: data.encryptionKeyHash.present
          ? data.encryptionKeyHash.value
          : this.encryptionKeyHash,
      lastUpdated: data.lastUpdated.present
          ? data.lastUpdated.value
          : this.lastUpdated,
      version: data.version.present ? data.version.value : this.version,
      parentCid: data.parentCid.present ? data.parentCid.value : this.parentCid,
      siblingCids: data.siblingCids.present
          ? data.siblingCids.value
          : this.siblingCids,
      rootCid: data.rootCid.present ? data.rootCid.value : this.rootCid,
      publisherKey: data.publisherKey.present
          ? data.publisherKey.value
          : this.publisherKey,
      signature: data.signature.present ? data.signature.value : this.signature,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentManifest(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('author: $author, ')
          ..write('tags: $tags, ')
          ..write('category: $category, ')
          ..write('metadata: $metadata, ')
          ..write('isEncrypted: $isEncrypted, ')
          ..write('encryptionKey: $encryptionKey, ')
          ..write('encryptionKeyHash: $encryptionKeyHash, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('version: $version, ')
          ..write('parentCid: $parentCid, ')
          ..write('siblingCids: $siblingCids, ')
          ..write('rootCid: $rootCid, ')
          ..write('publisherKey: $publisherKey, ')
          ..write('signature: $signature')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    uuid,
    title,
    description,
    author,
    tags,
    category,
    metadata,
    isEncrypted,
    encryptionKey,
    encryptionKeyHash,
    lastUpdated,
    version,
    parentCid,
    siblingCids,
    rootCid,
    publisherKey,
    signature,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentManifest &&
          other.id == this.id &&
          other.uuid == this.uuid &&
          other.title == this.title &&
          other.description == this.description &&
          other.author == this.author &&
          other.tags == this.tags &&
          other.category == this.category &&
          other.metadata == this.metadata &&
          other.isEncrypted == this.isEncrypted &&
          other.encryptionKey == this.encryptionKey &&
          other.encryptionKeyHash == this.encryptionKeyHash &&
          other.lastUpdated == this.lastUpdated &&
          other.version == this.version &&
          other.parentCid == this.parentCid &&
          other.siblingCids == this.siblingCids &&
          other.rootCid == this.rootCid &&
          other.publisherKey == this.publisherKey &&
          other.signature == this.signature);
}

class ContentManifestsCompanion extends UpdateCompanion<ContentManifest> {
  final Value<int> id;
  final Value<String> uuid;
  final Value<String> title;
  final Value<String?> description;
  final Value<String?> author;
  final Value<String?> tags;
  final Value<String> category;
  final Value<String?> metadata;
  final Value<bool> isEncrypted;
  final Value<String?> encryptionKey;
  final Value<String?> encryptionKeyHash;
  final Value<DateTime> lastUpdated;
  final Value<int> version;
  final Value<String?> parentCid;
  final Value<String?> siblingCids;
  final Value<String?> rootCid;
  final Value<String?> publisherKey;
  final Value<String?> signature;
  const ContentManifestsCompanion({
    this.id = const Value.absent(),
    this.uuid = const Value.absent(),
    this.title = const Value.absent(),
    this.description = const Value.absent(),
    this.author = const Value.absent(),
    this.tags = const Value.absent(),
    this.category = const Value.absent(),
    this.metadata = const Value.absent(),
    this.isEncrypted = const Value.absent(),
    this.encryptionKey = const Value.absent(),
    this.encryptionKeyHash = const Value.absent(),
    this.lastUpdated = const Value.absent(),
    this.version = const Value.absent(),
    this.parentCid = const Value.absent(),
    this.siblingCids = const Value.absent(),
    this.rootCid = const Value.absent(),
    this.publisherKey = const Value.absent(),
    this.signature = const Value.absent(),
  });
  ContentManifestsCompanion.insert({
    this.id = const Value.absent(),
    required String uuid,
    required String title,
    this.description = const Value.absent(),
    this.author = const Value.absent(),
    this.tags = const Value.absent(),
    this.category = const Value.absent(),
    this.metadata = const Value.absent(),
    this.isEncrypted = const Value.absent(),
    this.encryptionKey = const Value.absent(),
    this.encryptionKeyHash = const Value.absent(),
    required DateTime lastUpdated,
    this.version = const Value.absent(),
    this.parentCid = const Value.absent(),
    this.siblingCids = const Value.absent(),
    this.rootCid = const Value.absent(),
    this.publisherKey = const Value.absent(),
    this.signature = const Value.absent(),
  }) : uuid = Value(uuid),
       title = Value(title),
       lastUpdated = Value(lastUpdated);
  static Insertable<ContentManifest> custom({
    Expression<int>? id,
    Expression<String>? uuid,
    Expression<String>? title,
    Expression<String>? description,
    Expression<String>? author,
    Expression<String>? tags,
    Expression<String>? category,
    Expression<String>? metadata,
    Expression<bool>? isEncrypted,
    Expression<String>? encryptionKey,
    Expression<String>? encryptionKeyHash,
    Expression<DateTime>? lastUpdated,
    Expression<int>? version,
    Expression<String>? parentCid,
    Expression<String>? siblingCids,
    Expression<String>? rootCid,
    Expression<String>? publisherKey,
    Expression<String>? signature,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (uuid != null) 'uuid': uuid,
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (author != null) 'author': author,
      if (tags != null) 'tags': tags,
      if (category != null) 'category': category,
      if (metadata != null) 'metadata': metadata,
      if (isEncrypted != null) 'is_encrypted': isEncrypted,
      if (encryptionKey != null) 'encryption_key': encryptionKey,
      if (encryptionKeyHash != null) 'encryption_key_hash': encryptionKeyHash,
      if (lastUpdated != null) 'last_updated': lastUpdated,
      if (version != null) 'version': version,
      if (parentCid != null) 'parent_cid': parentCid,
      if (siblingCids != null) 'sibling_cids': siblingCids,
      if (rootCid != null) 'root_cid': rootCid,
      if (publisherKey != null) 'publisher_key': publisherKey,
      if (signature != null) 'signature': signature,
    });
  }

  ContentManifestsCompanion copyWith({
    Value<int>? id,
    Value<String>? uuid,
    Value<String>? title,
    Value<String?>? description,
    Value<String?>? author,
    Value<String?>? tags,
    Value<String>? category,
    Value<String?>? metadata,
    Value<bool>? isEncrypted,
    Value<String?>? encryptionKey,
    Value<String?>? encryptionKeyHash,
    Value<DateTime>? lastUpdated,
    Value<int>? version,
    Value<String?>? parentCid,
    Value<String?>? siblingCids,
    Value<String?>? rootCid,
    Value<String?>? publisherKey,
    Value<String?>? signature,
  }) {
    return ContentManifestsCompanion(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      title: title ?? this.title,
      description: description ?? this.description,
      author: author ?? this.author,
      tags: tags ?? this.tags,
      category: category ?? this.category,
      metadata: metadata ?? this.metadata,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      encryptionKeyHash: encryptionKeyHash ?? this.encryptionKeyHash,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      version: version ?? this.version,
      parentCid: parentCid ?? this.parentCid,
      siblingCids: siblingCids ?? this.siblingCids,
      rootCid: rootCid ?? this.rootCid,
      publisherKey: publisherKey ?? this.publisherKey,
      signature: signature ?? this.signature,
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
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
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
    if (encryptionKeyHash.present) {
      map['encryption_key_hash'] = Variable<String>(encryptionKeyHash.value);
    }
    if (lastUpdated.present) {
      map['last_updated'] = Variable<DateTime>(lastUpdated.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (parentCid.present) {
      map['parent_cid'] = Variable<String>(parentCid.value);
    }
    if (siblingCids.present) {
      map['sibling_cids'] = Variable<String>(siblingCids.value);
    }
    if (rootCid.present) {
      map['root_cid'] = Variable<String>(rootCid.value);
    }
    if (publisherKey.present) {
      map['publisher_key'] = Variable<String>(publisherKey.value);
    }
    if (signature.present) {
      map['signature'] = Variable<String>(signature.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentManifestsCompanion(')
          ..write('id: $id, ')
          ..write('uuid: $uuid, ')
          ..write('title: $title, ')
          ..write('description: $description, ')
          ..write('author: $author, ')
          ..write('tags: $tags, ')
          ..write('category: $category, ')
          ..write('metadata: $metadata, ')
          ..write('isEncrypted: $isEncrypted, ')
          ..write('encryptionKey: $encryptionKey, ')
          ..write('encryptionKeyHash: $encryptionKeyHash, ')
          ..write('lastUpdated: $lastUpdated, ')
          ..write('version: $version, ')
          ..write('parentCid: $parentCid, ')
          ..write('siblingCids: $siblingCids, ')
          ..write('rootCid: $rootCid, ')
          ..write('publisherKey: $publisherKey, ')
          ..write('signature: $signature')
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
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _cidMeta = const VerificationMeta('cid');
  @override
  late final GeneratedColumn<String> cid = GeneratedColumn<String>(
    'cid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _manifestIdMeta = const VerificationMeta(
    'manifestId',
  );
  @override
  late final GeneratedColumn<int> manifestId = GeneratedColumn<int>(
    'manifest_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES content_manifests (id)',
    ),
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _resolutionMeta = const VerificationMeta(
    'resolution',
  );
  @override
  late final GeneratedColumn<String> resolution = GeneratedColumn<String>(
    'resolution',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdDataMeta = const VerificationMeta(
    'createdData',
  );
  @override
  late final GeneratedColumn<DateTime> createdData = GeneratedColumn<DateTime>(
    'created_data',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isPinnedMeta = const VerificationMeta(
    'isPinned',
  );
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
    'is_pinned',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_pinned" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _peerCountMeta = const VerificationMeta(
    'peerCount',
  );
  @override
  late final GeneratedColumn<int> peerCount = GeneratedColumn<int>(
    'peer_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastHealthCheckMeta = const VerificationMeta(
    'lastHealthCheck',
  );
  @override
  late final GeneratedColumn<DateTime> lastHealthCheck =
      GeneratedColumn<DateTime>(
        'last_health_check',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cid,
    manifestId,
    language,
    resolution,
    format,
    sizeBytes,
    createdData,
    isPinned,
    peerCount,
    lastHealthCheck,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'content_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ContentVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cid')) {
      context.handle(
        _cidMeta,
        cid.isAcceptableOrUnknown(data['cid']!, _cidMeta),
      );
    } else if (isInserting) {
      context.missing(_cidMeta);
    }
    if (data.containsKey('manifest_id')) {
      context.handle(
        _manifestIdMeta,
        manifestId.isAcceptableOrUnknown(data['manifest_id']!, _manifestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_manifestIdMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    } else if (isInserting) {
      context.missing(_languageMeta);
    }
    if (data.containsKey('resolution')) {
      context.handle(
        _resolutionMeta,
        resolution.isAcceptableOrUnknown(data['resolution']!, _resolutionMeta),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('created_data')) {
      context.handle(
        _createdDataMeta,
        createdData.isAcceptableOrUnknown(
          data['created_data']!,
          _createdDataMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdDataMeta);
    }
    if (data.containsKey('is_pinned')) {
      context.handle(
        _isPinnedMeta,
        isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta),
      );
    }
    if (data.containsKey('peer_count')) {
      context.handle(
        _peerCountMeta,
        peerCount.isAcceptableOrUnknown(data['peer_count']!, _peerCountMeta),
      );
    }
    if (data.containsKey('last_health_check')) {
      context.handle(
        _lastHealthCheckMeta,
        lastHealthCheck.isAcceptableOrUnknown(
          data['last_health_check']!,
          _lastHealthCheckMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ContentVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ContentVersion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      cid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cid'],
      )!,
      manifestId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}manifest_id'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      )!,
      resolution: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution'],
      ),
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      createdData: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_data'],
      )!,
      isPinned: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_pinned'],
      )!,
      peerCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}peer_count'],
      )!,
      lastHealthCheck: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_health_check'],
      ),
    );
  }

  @override
  $ContentVersionsTable createAlias(String alias) {
    return $ContentVersionsTable(attachedDatabase, alias);
  }
}

class ContentVersion extends DataClass implements Insertable<ContentVersion> {
  final int id;
  final String cid;
  final int manifestId;
  final String language;
  final String? resolution;
  final String format;
  final int sizeBytes;
  final DateTime createdData;
  final bool isPinned;
  final int peerCount;
  final DateTime? lastHealthCheck;
  const ContentVersion({
    required this.id,
    required this.cid,
    required this.manifestId,
    required this.language,
    this.resolution,
    required this.format,
    required this.sizeBytes,
    required this.createdData,
    required this.isPinned,
    required this.peerCount,
    this.lastHealthCheck,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cid'] = Variable<String>(cid);
    map['manifest_id'] = Variable<int>(manifestId);
    map['language'] = Variable<String>(language);
    if (!nullToAbsent || resolution != null) {
      map['resolution'] = Variable<String>(resolution);
    }
    map['format'] = Variable<String>(format);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['created_data'] = Variable<DateTime>(createdData);
    map['is_pinned'] = Variable<bool>(isPinned);
    map['peer_count'] = Variable<int>(peerCount);
    if (!nullToAbsent || lastHealthCheck != null) {
      map['last_health_check'] = Variable<DateTime>(lastHealthCheck);
    }
    return map;
  }

  ContentVersionsCompanion toCompanion(bool nullToAbsent) {
    return ContentVersionsCompanion(
      id: Value(id),
      cid: Value(cid),
      manifestId: Value(manifestId),
      language: Value(language),
      resolution: resolution == null && nullToAbsent
          ? const Value.absent()
          : Value(resolution),
      format: Value(format),
      sizeBytes: Value(sizeBytes),
      createdData: Value(createdData),
      isPinned: Value(isPinned),
      peerCount: Value(peerCount),
      lastHealthCheck: lastHealthCheck == null && nullToAbsent
          ? const Value.absent()
          : Value(lastHealthCheck),
    );
  }

  factory ContentVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ContentVersion(
      id: serializer.fromJson<int>(json['id']),
      cid: serializer.fromJson<String>(json['cid']),
      manifestId: serializer.fromJson<int>(json['manifestId']),
      language: serializer.fromJson<String>(json['language']),
      resolution: serializer.fromJson<String?>(json['resolution']),
      format: serializer.fromJson<String>(json['format']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      createdData: serializer.fromJson<DateTime>(json['createdData']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      peerCount: serializer.fromJson<int>(json['peerCount']),
      lastHealthCheck: serializer.fromJson<DateTime?>(json['lastHealthCheck']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cid': serializer.toJson<String>(cid),
      'manifestId': serializer.toJson<int>(manifestId),
      'language': serializer.toJson<String>(language),
      'resolution': serializer.toJson<String?>(resolution),
      'format': serializer.toJson<String>(format),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'createdData': serializer.toJson<DateTime>(createdData),
      'isPinned': serializer.toJson<bool>(isPinned),
      'peerCount': serializer.toJson<int>(peerCount),
      'lastHealthCheck': serializer.toJson<DateTime?>(lastHealthCheck),
    };
  }

  ContentVersion copyWith({
    int? id,
    String? cid,
    int? manifestId,
    String? language,
    Value<String?> resolution = const Value.absent(),
    String? format,
    int? sizeBytes,
    DateTime? createdData,
    bool? isPinned,
    int? peerCount,
    Value<DateTime?> lastHealthCheck = const Value.absent(),
  }) => ContentVersion(
    id: id ?? this.id,
    cid: cid ?? this.cid,
    manifestId: manifestId ?? this.manifestId,
    language: language ?? this.language,
    resolution: resolution.present ? resolution.value : this.resolution,
    format: format ?? this.format,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    createdData: createdData ?? this.createdData,
    isPinned: isPinned ?? this.isPinned,
    peerCount: peerCount ?? this.peerCount,
    lastHealthCheck: lastHealthCheck.present
        ? lastHealthCheck.value
        : this.lastHealthCheck,
  );
  ContentVersion copyWithCompanion(ContentVersionsCompanion data) {
    return ContentVersion(
      id: data.id.present ? data.id.value : this.id,
      cid: data.cid.present ? data.cid.value : this.cid,
      manifestId: data.manifestId.present
          ? data.manifestId.value
          : this.manifestId,
      language: data.language.present ? data.language.value : this.language,
      resolution: data.resolution.present
          ? data.resolution.value
          : this.resolution,
      format: data.format.present ? data.format.value : this.format,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      createdData: data.createdData.present
          ? data.createdData.value
          : this.createdData,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      peerCount: data.peerCount.present ? data.peerCount.value : this.peerCount,
      lastHealthCheck: data.lastHealthCheck.present
          ? data.lastHealthCheck.value
          : this.lastHealthCheck,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ContentVersion(')
          ..write('id: $id, ')
          ..write('cid: $cid, ')
          ..write('manifestId: $manifestId, ')
          ..write('language: $language, ')
          ..write('resolution: $resolution, ')
          ..write('format: $format, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdData: $createdData, ')
          ..write('isPinned: $isPinned, ')
          ..write('peerCount: $peerCount, ')
          ..write('lastHealthCheck: $lastHealthCheck')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cid,
    manifestId,
    language,
    resolution,
    format,
    sizeBytes,
    createdData,
    isPinned,
    peerCount,
    lastHealthCheck,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContentVersion &&
          other.id == this.id &&
          other.cid == this.cid &&
          other.manifestId == this.manifestId &&
          other.language == this.language &&
          other.resolution == this.resolution &&
          other.format == this.format &&
          other.sizeBytes == this.sizeBytes &&
          other.createdData == this.createdData &&
          other.isPinned == this.isPinned &&
          other.peerCount == this.peerCount &&
          other.lastHealthCheck == this.lastHealthCheck);
}

class ContentVersionsCompanion extends UpdateCompanion<ContentVersion> {
  final Value<int> id;
  final Value<String> cid;
  final Value<int> manifestId;
  final Value<String> language;
  final Value<String?> resolution;
  final Value<String> format;
  final Value<int> sizeBytes;
  final Value<DateTime> createdData;
  final Value<bool> isPinned;
  final Value<int> peerCount;
  final Value<DateTime?> lastHealthCheck;
  const ContentVersionsCompanion({
    this.id = const Value.absent(),
    this.cid = const Value.absent(),
    this.manifestId = const Value.absent(),
    this.language = const Value.absent(),
    this.resolution = const Value.absent(),
    this.format = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.createdData = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.peerCount = const Value.absent(),
    this.lastHealthCheck = const Value.absent(),
  });
  ContentVersionsCompanion.insert({
    this.id = const Value.absent(),
    required String cid,
    required int manifestId,
    required String language,
    this.resolution = const Value.absent(),
    required String format,
    required int sizeBytes,
    required DateTime createdData,
    this.isPinned = const Value.absent(),
    this.peerCount = const Value.absent(),
    this.lastHealthCheck = const Value.absent(),
  }) : cid = Value(cid),
       manifestId = Value(manifestId),
       language = Value(language),
       format = Value(format),
       sizeBytes = Value(sizeBytes),
       createdData = Value(createdData);
  static Insertable<ContentVersion> custom({
    Expression<int>? id,
    Expression<String>? cid,
    Expression<int>? manifestId,
    Expression<String>? language,
    Expression<String>? resolution,
    Expression<String>? format,
    Expression<int>? sizeBytes,
    Expression<DateTime>? createdData,
    Expression<bool>? isPinned,
    Expression<int>? peerCount,
    Expression<DateTime>? lastHealthCheck,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cid != null) 'cid': cid,
      if (manifestId != null) 'manifest_id': manifestId,
      if (language != null) 'language': language,
      if (resolution != null) 'resolution': resolution,
      if (format != null) 'format': format,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (createdData != null) 'created_data': createdData,
      if (isPinned != null) 'is_pinned': isPinned,
      if (peerCount != null) 'peer_count': peerCount,
      if (lastHealthCheck != null) 'last_health_check': lastHealthCheck,
    });
  }

  ContentVersionsCompanion copyWith({
    Value<int>? id,
    Value<String>? cid,
    Value<int>? manifestId,
    Value<String>? language,
    Value<String?>? resolution,
    Value<String>? format,
    Value<int>? sizeBytes,
    Value<DateTime>? createdData,
    Value<bool>? isPinned,
    Value<int>? peerCount,
    Value<DateTime?>? lastHealthCheck,
  }) {
    return ContentVersionsCompanion(
      id: id ?? this.id,
      cid: cid ?? this.cid,
      manifestId: manifestId ?? this.manifestId,
      language: language ?? this.language,
      resolution: resolution ?? this.resolution,
      format: format ?? this.format,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      createdData: createdData ?? this.createdData,
      isPinned: isPinned ?? this.isPinned,
      peerCount: peerCount ?? this.peerCount,
      lastHealthCheck: lastHealthCheck ?? this.lastHealthCheck,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cid.present) {
      map['cid'] = Variable<String>(cid.value);
    }
    if (manifestId.present) {
      map['manifest_id'] = Variable<int>(manifestId.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (resolution.present) {
      map['resolution'] = Variable<String>(resolution.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (createdData.present) {
      map['created_data'] = Variable<DateTime>(createdData.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (peerCount.present) {
      map['peer_count'] = Variable<int>(peerCount.value);
    }
    if (lastHealthCheck.present) {
      map['last_health_check'] = Variable<DateTime>(lastHealthCheck.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ContentVersionsCompanion(')
          ..write('id: $id, ')
          ..write('cid: $cid, ')
          ..write('manifestId: $manifestId, ')
          ..write('language: $language, ')
          ..write('resolution: $resolution, ')
          ..write('format: $format, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('createdData: $createdData, ')
          ..write('isPinned: $isPinned, ')
          ..write('peerCount: $peerCount, ')
          ..write('lastHealthCheck: $lastHealthCheck')
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
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _validatorIdMeta = const VerificationMeta(
    'validatorId',
  );
  @override
  late final GeneratedColumn<String> validatorId = GeneratedColumn<String>(
    'validator_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetCidMeta = const VerificationMeta(
    'targetCid',
  );
  @override
  late final GeneratedColumn<String> targetCid = GeneratedColumn<String>(
    'target_cid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scoreMeta = const VerificationMeta('score');
  @override
  late final GeneratedColumn<int> score = GeneratedColumn<int>(
    'score',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signatureMeta = const VerificationMeta(
    'signature',
  );
  @override
  late final GeneratedColumn<String> signature = GeneratedColumn<String>(
    'signature',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    validatorId,
    targetCid,
    score,
    timestamp,
    signature,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'honor_validations';
  @override
  VerificationContext validateIntegrity(
    Insertable<HonorValidation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('validator_id')) {
      context.handle(
        _validatorIdMeta,
        validatorId.isAcceptableOrUnknown(
          data['validator_id']!,
          _validatorIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_validatorIdMeta);
    }
    if (data.containsKey('target_cid')) {
      context.handle(
        _targetCidMeta,
        targetCid.isAcceptableOrUnknown(data['target_cid']!, _targetCidMeta),
      );
    } else if (isInserting) {
      context.missing(_targetCidMeta);
    }
    if (data.containsKey('score')) {
      context.handle(
        _scoreMeta,
        score.isAcceptableOrUnknown(data['score']!, _scoreMeta),
      );
    } else if (isInserting) {
      context.missing(_scoreMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('signature')) {
      context.handle(
        _signatureMeta,
        signature.isAcceptableOrUnknown(data['signature']!, _signatureMeta),
      );
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
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      validatorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}validator_id'],
      )!,
      targetCid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_cid'],
      )!,
      score: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}score'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      signature: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signature'],
      )!,
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
  const HonorValidation({
    required this.id,
    required this.validatorId,
    required this.targetCid,
    required this.score,
    required this.timestamp,
    required this.signature,
  });
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

  factory HonorValidation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
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

  HonorValidation copyWith({
    int? id,
    String? validatorId,
    String? targetCid,
    int? score,
    DateTime? timestamp,
    String? signature,
  }) => HonorValidation(
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
      validatorId: data.validatorId.present
          ? data.validatorId.value
          : this.validatorId,
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
  }) : validatorId = Value(validatorId),
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

  HonorValidationsCompanion copyWith({
    Value<int>? id,
    Value<String>? validatorId,
    Value<String>? targetCid,
    Value<int>? score,
    Value<DateTime>? timestamp,
    Value<String>? signature,
  }) {
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

class $UserProfilesTable extends UserProfiles
    with TableInfo<$UserProfilesTable, UserProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _reputationMeta = const VerificationMeta(
    'reputation',
  );
  @override
  late final GeneratedColumn<int> reputation = GeneratedColumn<int>(
    'reputation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _badgesMeta = const VerificationMeta('badges');
  @override
  late final GeneratedColumn<String> badges = GeneratedColumn<String>(
    'badges',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastActiveMeta = const VerificationMeta(
    'lastActive',
  );
  @override
  late final GeneratedColumn<DateTime> lastActive = GeneratedColumn<DateTime>(
    'last_active',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    publicKey,
    reputation,
    badges,
    lastActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserProfile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_publicKeyMeta);
    }
    if (data.containsKey('reputation')) {
      context.handle(
        _reputationMeta,
        reputation.isAcceptableOrUnknown(data['reputation']!, _reputationMeta),
      );
    } else if (isInserting) {
      context.missing(_reputationMeta);
    }
    if (data.containsKey('badges')) {
      context.handle(
        _badgesMeta,
        badges.isAcceptableOrUnknown(data['badges']!, _badgesMeta),
      );
    }
    if (data.containsKey('last_active')) {
      context.handle(
        _lastActiveMeta,
        lastActive.isAcceptableOrUnknown(data['last_active']!, _lastActiveMeta),
      );
    } else if (isInserting) {
      context.missing(_lastActiveMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserProfile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      )!,
      reputation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reputation'],
      )!,
      badges: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}badges'],
      ),
      lastActive: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_active'],
      )!,
    );
  }

  @override
  $UserProfilesTable createAlias(String alias) {
    return $UserProfilesTable(attachedDatabase, alias);
  }
}

class UserProfile extends DataClass implements Insertable<UserProfile> {
  final int id;
  final String publicKey;
  final int reputation;
  final String? badges;
  final DateTime lastActive;
  const UserProfile({
    required this.id,
    required this.publicKey,
    required this.reputation,
    this.badges,
    required this.lastActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['public_key'] = Variable<String>(publicKey);
    map['reputation'] = Variable<int>(reputation);
    if (!nullToAbsent || badges != null) {
      map['badges'] = Variable<String>(badges);
    }
    map['last_active'] = Variable<DateTime>(lastActive);
    return map;
  }

  UserProfilesCompanion toCompanion(bool nullToAbsent) {
    return UserProfilesCompanion(
      id: Value(id),
      publicKey: Value(publicKey),
      reputation: Value(reputation),
      badges: badges == null && nullToAbsent
          ? const Value.absent()
          : Value(badges),
      lastActive: Value(lastActive),
    );
  }

  factory UserProfile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserProfile(
      id: serializer.fromJson<int>(json['id']),
      publicKey: serializer.fromJson<String>(json['publicKey']),
      reputation: serializer.fromJson<int>(json['reputation']),
      badges: serializer.fromJson<String?>(json['badges']),
      lastActive: serializer.fromJson<DateTime>(json['lastActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'publicKey': serializer.toJson<String>(publicKey),
      'reputation': serializer.toJson<int>(reputation),
      'badges': serializer.toJson<String?>(badges),
      'lastActive': serializer.toJson<DateTime>(lastActive),
    };
  }

  UserProfile copyWith({
    int? id,
    String? publicKey,
    int? reputation,
    Value<String?> badges = const Value.absent(),
    DateTime? lastActive,
  }) => UserProfile(
    id: id ?? this.id,
    publicKey: publicKey ?? this.publicKey,
    reputation: reputation ?? this.reputation,
    badges: badges.present ? badges.value : this.badges,
    lastActive: lastActive ?? this.lastActive,
  );
  UserProfile copyWithCompanion(UserProfilesCompanion data) {
    return UserProfile(
      id: data.id.present ? data.id.value : this.id,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      reputation: data.reputation.present
          ? data.reputation.value
          : this.reputation,
      badges: data.badges.present ? data.badges.value : this.badges,
      lastActive: data.lastActive.present
          ? data.lastActive.value
          : this.lastActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserProfile(')
          ..write('id: $id, ')
          ..write('publicKey: $publicKey, ')
          ..write('reputation: $reputation, ')
          ..write('badges: $badges, ')
          ..write('lastActive: $lastActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, publicKey, reputation, badges, lastActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserProfile &&
          other.id == this.id &&
          other.publicKey == this.publicKey &&
          other.reputation == this.reputation &&
          other.badges == this.badges &&
          other.lastActive == this.lastActive);
}

class UserProfilesCompanion extends UpdateCompanion<UserProfile> {
  final Value<int> id;
  final Value<String> publicKey;
  final Value<int> reputation;
  final Value<String?> badges;
  final Value<DateTime> lastActive;
  const UserProfilesCompanion({
    this.id = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.reputation = const Value.absent(),
    this.badges = const Value.absent(),
    this.lastActive = const Value.absent(),
  });
  UserProfilesCompanion.insert({
    this.id = const Value.absent(),
    required String publicKey,
    required int reputation,
    this.badges = const Value.absent(),
    required DateTime lastActive,
  }) : publicKey = Value(publicKey),
       reputation = Value(reputation),
       lastActive = Value(lastActive);
  static Insertable<UserProfile> custom({
    Expression<int>? id,
    Expression<String>? publicKey,
    Expression<int>? reputation,
    Expression<String>? badges,
    Expression<DateTime>? lastActive,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (publicKey != null) 'public_key': publicKey,
      if (reputation != null) 'reputation': reputation,
      if (badges != null) 'badges': badges,
      if (lastActive != null) 'last_active': lastActive,
    });
  }

  UserProfilesCompanion copyWith({
    Value<int>? id,
    Value<String>? publicKey,
    Value<int>? reputation,
    Value<String?>? badges,
    Value<DateTime>? lastActive,
  }) {
    return UserProfilesCompanion(
      id: id ?? this.id,
      publicKey: publicKey ?? this.publicKey,
      reputation: reputation ?? this.reputation,
      badges: badges ?? this.badges,
      lastActive: lastActive ?? this.lastActive,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (reputation.present) {
      map['reputation'] = Variable<int>(reputation.value);
    }
    if (badges.present) {
      map['badges'] = Variable<String>(badges.value);
    }
    if (lastActive.present) {
      map['last_active'] = Variable<DateTime>(lastActive.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserProfilesCompanion(')
          ..write('id: $id, ')
          ..write('publicKey: $publicKey, ')
          ..write('reputation: $reputation, ')
          ..write('badges: $badges, ')
          ..write('lastActive: $lastActive')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ContentManifestsTable contentManifests = $ContentManifestsTable(
    this,
  );
  late final $ContentVersionsTable contentVersions = $ContentVersionsTable(
    this,
  );
  late final $HonorValidationsTable honorValidations = $HonorValidationsTable(
    this,
  );
  late final $UserProfilesTable userProfiles = $UserProfilesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    contentManifests,
    contentVersions,
    honorValidations,
    userProfiles,
  ];
}

typedef $$ContentManifestsTableCreateCompanionBuilder =
    ContentManifestsCompanion Function({
      Value<int> id,
      required String uuid,
      required String title,
      Value<String?> description,
      Value<String?> author,
      Value<String?> tags,
      Value<String> category,
      Value<String?> metadata,
      Value<bool> isEncrypted,
      Value<String?> encryptionKey,
      Value<String?> encryptionKeyHash,
      required DateTime lastUpdated,
      Value<int> version,
      Value<String?> parentCid,
      Value<String?> siblingCids,
      Value<String?> rootCid,
      Value<String?> publisherKey,
      Value<String?> signature,
    });
typedef $$ContentManifestsTableUpdateCompanionBuilder =
    ContentManifestsCompanion Function({
      Value<int> id,
      Value<String> uuid,
      Value<String> title,
      Value<String?> description,
      Value<String?> author,
      Value<String?> tags,
      Value<String> category,
      Value<String?> metadata,
      Value<bool> isEncrypted,
      Value<String?> encryptionKey,
      Value<String?> encryptionKeyHash,
      Value<DateTime> lastUpdated,
      Value<int> version,
      Value<String?> parentCid,
      Value<String?> siblingCids,
      Value<String?> rootCid,
      Value<String?> publisherKey,
      Value<String?> signature,
    });

final class $$ContentManifestsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ContentManifestsTable, ContentManifest> {
  $$ContentManifestsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ContentVersionsTable, List<ContentVersion>>
  _contentVersionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.contentVersions,
    aliasName: $_aliasNameGenerator(
      db.contentManifests.id,
      db.contentVersions.manifestId,
    ),
  );

  $$ContentVersionsTableProcessedTableManager get contentVersionsRefs {
    final manager = $$ContentVersionsTableTableManager(
      $_db,
      $_db.contentVersions,
    ).filter((f) => f.manifestId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _contentVersionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
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
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEncrypted => $composableBuilder(
    column: $table.isEncrypted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptionKey => $composableBuilder(
    column: $table.encryptionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptionKeyHash => $composableBuilder(
    column: $table.encryptionKeyHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentCid => $composableBuilder(
    column: $table.parentCid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get siblingCids => $composableBuilder(
    column: $table.siblingCids,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rootCid => $composableBuilder(
    column: $table.rootCid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publisherKey => $composableBuilder(
    column: $table.publisherKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> contentVersionsRefs(
    Expression<bool> Function($$ContentVersionsTableFilterComposer f) f,
  ) {
    final $$ContentVersionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.contentVersions,
      getReferencedColumn: (t) => t.manifestId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContentVersionsTableFilterComposer(
            $db: $db,
            $table: $db.contentVersions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
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
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uuid => $composableBuilder(
    column: $table.uuid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metadata => $composableBuilder(
    column: $table.metadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEncrypted => $composableBuilder(
    column: $table.isEncrypted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptionKey => $composableBuilder(
    column: $table.encryptionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptionKeyHash => $composableBuilder(
    column: $table.encryptionKeyHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentCid => $composableBuilder(
    column: $table.parentCid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get siblingCids => $composableBuilder(
    column: $table.siblingCids,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rootCid => $composableBuilder(
    column: $table.rootCid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publisherKey => $composableBuilder(
    column: $table.publisherKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );
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

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get metadata =>
      $composableBuilder(column: $table.metadata, builder: (column) => column);

  GeneratedColumn<bool> get isEncrypted => $composableBuilder(
    column: $table.isEncrypted,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptionKey => $composableBuilder(
    column: $table.encryptionKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get encryptionKeyHash => $composableBuilder(
    column: $table.encryptionKeyHash,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastUpdated => $composableBuilder(
    column: $table.lastUpdated,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get parentCid =>
      $composableBuilder(column: $table.parentCid, builder: (column) => column);

  GeneratedColumn<String> get siblingCids => $composableBuilder(
    column: $table.siblingCids,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rootCid =>
      $composableBuilder(column: $table.rootCid, builder: (column) => column);

  GeneratedColumn<String> get publisherKey => $composableBuilder(
    column: $table.publisherKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);

  Expression<T> contentVersionsRefs<T extends Object>(
    Expression<T> Function($$ContentVersionsTableAnnotationComposer a) f,
  ) {
    final $$ContentVersionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.contentVersions,
      getReferencedColumn: (t) => t.manifestId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContentVersionsTableAnnotationComposer(
            $db: $db,
            $table: $db.contentVersions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ContentManifestsTableTableManager
    extends
        RootTableManager<
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
          PrefetchHooks Function({bool contentVersionsRefs})
        > {
  $$ContentManifestsTableTableManager(
    _$AppDatabase db,
    $ContentManifestsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContentManifestsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContentManifestsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContentManifestsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> uuid = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> tags = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<bool> isEncrypted = const Value.absent(),
                Value<String?> encryptionKey = const Value.absent(),
                Value<String?> encryptionKeyHash = const Value.absent(),
                Value<DateTime> lastUpdated = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String?> parentCid = const Value.absent(),
                Value<String?> siblingCids = const Value.absent(),
                Value<String?> rootCid = const Value.absent(),
                Value<String?> publisherKey = const Value.absent(),
                Value<String?> signature = const Value.absent(),
              }) => ContentManifestsCompanion(
                id: id,
                uuid: uuid,
                title: title,
                description: description,
                author: author,
                tags: tags,
                category: category,
                metadata: metadata,
                isEncrypted: isEncrypted,
                encryptionKey: encryptionKey,
                encryptionKeyHash: encryptionKeyHash,
                lastUpdated: lastUpdated,
                version: version,
                parentCid: parentCid,
                siblingCids: siblingCids,
                rootCid: rootCid,
                publisherKey: publisherKey,
                signature: signature,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String uuid,
                required String title,
                Value<String?> description = const Value.absent(),
                Value<String?> author = const Value.absent(),
                Value<String?> tags = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> metadata = const Value.absent(),
                Value<bool> isEncrypted = const Value.absent(),
                Value<String?> encryptionKey = const Value.absent(),
                Value<String?> encryptionKeyHash = const Value.absent(),
                required DateTime lastUpdated,
                Value<int> version = const Value.absent(),
                Value<String?> parentCid = const Value.absent(),
                Value<String?> siblingCids = const Value.absent(),
                Value<String?> rootCid = const Value.absent(),
                Value<String?> publisherKey = const Value.absent(),
                Value<String?> signature = const Value.absent(),
              }) => ContentManifestsCompanion.insert(
                id: id,
                uuid: uuid,
                title: title,
                description: description,
                author: author,
                tags: tags,
                category: category,
                metadata: metadata,
                isEncrypted: isEncrypted,
                encryptionKey: encryptionKey,
                encryptionKeyHash: encryptionKeyHash,
                lastUpdated: lastUpdated,
                version: version,
                parentCid: parentCid,
                siblingCids: siblingCids,
                rootCid: rootCid,
                publisherKey: publisherKey,
                signature: signature,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ContentManifestsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({contentVersionsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (contentVersionsRefs) db.contentVersions,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (contentVersionsRefs)
                    await $_getPrefetchedData<
                      ContentManifest,
                      $ContentManifestsTable,
                      ContentVersion
                    >(
                      currentTable: table,
                      referencedTable: $$ContentManifestsTableReferences
                          ._contentVersionsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ContentManifestsTableReferences(
                            db,
                            table,
                            p0,
                          ).contentVersionsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.manifestId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ContentManifestsTableProcessedTableManager =
    ProcessedTableManager<
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
      PrefetchHooks Function({bool contentVersionsRefs})
    >;
typedef $$ContentVersionsTableCreateCompanionBuilder =
    ContentVersionsCompanion Function({
      Value<int> id,
      required String cid,
      required int manifestId,
      required String language,
      Value<String?> resolution,
      required String format,
      required int sizeBytes,
      required DateTime createdData,
      Value<bool> isPinned,
      Value<int> peerCount,
      Value<DateTime?> lastHealthCheck,
    });
typedef $$ContentVersionsTableUpdateCompanionBuilder =
    ContentVersionsCompanion Function({
      Value<int> id,
      Value<String> cid,
      Value<int> manifestId,
      Value<String> language,
      Value<String?> resolution,
      Value<String> format,
      Value<int> sizeBytes,
      Value<DateTime> createdData,
      Value<bool> isPinned,
      Value<int> peerCount,
      Value<DateTime?> lastHealthCheck,
    });

final class $$ContentVersionsTableReferences
    extends
        BaseReferences<_$AppDatabase, $ContentVersionsTable, ContentVersion> {
  $$ContentVersionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ContentManifestsTable _manifestIdTable(_$AppDatabase db) =>
      db.contentManifests.createAlias(
        $_aliasNameGenerator(
          db.contentVersions.manifestId,
          db.contentManifests.id,
        ),
      );

  $$ContentManifestsTableProcessedTableManager get manifestId {
    final $_column = $_itemColumn<int>('manifest_id')!;

    final manager = $$ContentManifestsTableTableManager(
      $_db,
      $_db.contentManifests,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_manifestIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
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
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cid => $composableBuilder(
    column: $table.cid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdData => $composableBuilder(
    column: $table.createdData,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get peerCount => $composableBuilder(
    column: $table.peerCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastHealthCheck => $composableBuilder(
    column: $table.lastHealthCheck,
    builder: (column) => ColumnFilters(column),
  );

  $$ContentManifestsTableFilterComposer get manifestId {
    final $$ContentManifestsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manifestId,
      referencedTable: $db.contentManifests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContentManifestsTableFilterComposer(
            $db: $db,
            $table: $db.contentManifests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
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
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cid => $composableBuilder(
    column: $table.cid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdData => $composableBuilder(
    column: $table.createdData,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPinned => $composableBuilder(
    column: $table.isPinned,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get peerCount => $composableBuilder(
    column: $table.peerCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastHealthCheck => $composableBuilder(
    column: $table.lastHealthCheck,
    builder: (column) => ColumnOrderings(column),
  );

  $$ContentManifestsTableOrderingComposer get manifestId {
    final $$ContentManifestsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manifestId,
      referencedTable: $db.contentManifests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContentManifestsTableOrderingComposer(
            $db: $db,
            $table: $db.contentManifests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
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

  GeneratedColumn<String> get resolution => $composableBuilder(
    column: $table.resolution,
    builder: (column) => column,
  );

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdData => $composableBuilder(
    column: $table.createdData,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<int> get peerCount =>
      $composableBuilder(column: $table.peerCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastHealthCheck => $composableBuilder(
    column: $table.lastHealthCheck,
    builder: (column) => column,
  );

  $$ContentManifestsTableAnnotationComposer get manifestId {
    final $$ContentManifestsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.manifestId,
      referencedTable: $db.contentManifests,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ContentManifestsTableAnnotationComposer(
            $db: $db,
            $table: $db.contentManifests,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ContentVersionsTableTableManager
    extends
        RootTableManager<
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
          PrefetchHooks Function({bool manifestId})
        > {
  $$ContentVersionsTableTableManager(
    _$AppDatabase db,
    $ContentVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ContentVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ContentVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ContentVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> cid = const Value.absent(),
                Value<int> manifestId = const Value.absent(),
                Value<String> language = const Value.absent(),
                Value<String?> resolution = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<DateTime> createdData = const Value.absent(),
                Value<bool> isPinned = const Value.absent(),
                Value<int> peerCount = const Value.absent(),
                Value<DateTime?> lastHealthCheck = const Value.absent(),
              }) => ContentVersionsCompanion(
                id: id,
                cid: cid,
                manifestId: manifestId,
                language: language,
                resolution: resolution,
                format: format,
                sizeBytes: sizeBytes,
                createdData: createdData,
                isPinned: isPinned,
                peerCount: peerCount,
                lastHealthCheck: lastHealthCheck,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String cid,
                required int manifestId,
                required String language,
                Value<String?> resolution = const Value.absent(),
                required String format,
                required int sizeBytes,
                required DateTime createdData,
                Value<bool> isPinned = const Value.absent(),
                Value<int> peerCount = const Value.absent(),
                Value<DateTime?> lastHealthCheck = const Value.absent(),
              }) => ContentVersionsCompanion.insert(
                id: id,
                cid: cid,
                manifestId: manifestId,
                language: language,
                resolution: resolution,
                format: format,
                sizeBytes: sizeBytes,
                createdData: createdData,
                isPinned: isPinned,
                peerCount: peerCount,
                lastHealthCheck: lastHealthCheck,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ContentVersionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({manifestId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
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
                      dynamic
                    >
                  >(state) {
                    if (manifestId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.manifestId,
                                referencedTable:
                                    $$ContentVersionsTableReferences
                                        ._manifestIdTable(db),
                                referencedColumn:
                                    $$ContentVersionsTableReferences
                                        ._manifestIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ContentVersionsTableProcessedTableManager =
    ProcessedTableManager<
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
      PrefetchHooks Function({bool manifestId})
    >;
typedef $$HonorValidationsTableCreateCompanionBuilder =
    HonorValidationsCompanion Function({
      Value<int> id,
      required String validatorId,
      required String targetCid,
      required int score,
      required DateTime timestamp,
      required String signature,
    });
typedef $$HonorValidationsTableUpdateCompanionBuilder =
    HonorValidationsCompanion Function({
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
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get validatorId => $composableBuilder(
    column: $table.validatorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetCid => $composableBuilder(
    column: $table.targetCid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnFilters(column),
  );
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
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get validatorId => $composableBuilder(
    column: $table.validatorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetCid => $composableBuilder(
    column: $table.targetCid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get score => $composableBuilder(
    column: $table.score,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signature => $composableBuilder(
    column: $table.signature,
    builder: (column) => ColumnOrderings(column),
  );
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
    column: $table.validatorId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get targetCid =>
      $composableBuilder(column: $table.targetCid, builder: (column) => column);

  GeneratedColumn<int> get score =>
      $composableBuilder(column: $table.score, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<String> get signature =>
      $composableBuilder(column: $table.signature, builder: (column) => column);
}

class $$HonorValidationsTableTableManager
    extends
        RootTableManager<
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
            BaseReferences<
              _$AppDatabase,
              $HonorValidationsTable,
              HonorValidation
            >,
          ),
          HonorValidation,
          PrefetchHooks Function()
        > {
  $$HonorValidationsTableTableManager(
    _$AppDatabase db,
    $HonorValidationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HonorValidationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HonorValidationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HonorValidationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> validatorId = const Value.absent(),
                Value<String> targetCid = const Value.absent(),
                Value<int> score = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<String> signature = const Value.absent(),
              }) => HonorValidationsCompanion(
                id: id,
                validatorId: validatorId,
                targetCid: targetCid,
                score: score,
                timestamp: timestamp,
                signature: signature,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String validatorId,
                required String targetCid,
                required int score,
                required DateTime timestamp,
                required String signature,
              }) => HonorValidationsCompanion.insert(
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
        ),
      );
}

typedef $$HonorValidationsTableProcessedTableManager =
    ProcessedTableManager<
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
        BaseReferences<_$AppDatabase, $HonorValidationsTable, HonorValidation>,
      ),
      HonorValidation,
      PrefetchHooks Function()
    >;
typedef $$UserProfilesTableCreateCompanionBuilder =
    UserProfilesCompanion Function({
      Value<int> id,
      required String publicKey,
      required int reputation,
      Value<String?> badges,
      required DateTime lastActive,
    });
typedef $$UserProfilesTableUpdateCompanionBuilder =
    UserProfilesCompanion Function({
      Value<int> id,
      Value<String> publicKey,
      Value<int> reputation,
      Value<String?> badges,
      Value<DateTime> lastActive,
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
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reputation => $composableBuilder(
    column: $table.reputation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get badges => $composableBuilder(
    column: $table.badges,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastActive => $composableBuilder(
    column: $table.lastActive,
    builder: (column) => ColumnFilters(column),
  );
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
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reputation => $composableBuilder(
    column: $table.reputation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get badges => $composableBuilder(
    column: $table.badges,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastActive => $composableBuilder(
    column: $table.lastActive,
    builder: (column) => ColumnOrderings(column),
  );
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
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<int> get reputation => $composableBuilder(
    column: $table.reputation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get badges =>
      $composableBuilder(column: $table.badges, builder: (column) => column);

  GeneratedColumn<DateTime> get lastActive => $composableBuilder(
    column: $table.lastActive,
    builder: (column) => column,
  );
}

class $$UserProfilesTableTableManager
    extends
        RootTableManager<
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
            BaseReferences<_$AppDatabase, $UserProfilesTable, UserProfile>,
          ),
          UserProfile,
          PrefetchHooks Function()
        > {
  $$UserProfilesTableTableManager(_$AppDatabase db, $UserProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> publicKey = const Value.absent(),
                Value<int> reputation = const Value.absent(),
                Value<String?> badges = const Value.absent(),
                Value<DateTime> lastActive = const Value.absent(),
              }) => UserProfilesCompanion(
                id: id,
                publicKey: publicKey,
                reputation: reputation,
                badges: badges,
                lastActive: lastActive,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String publicKey,
                required int reputation,
                Value<String?> badges = const Value.absent(),
                required DateTime lastActive,
              }) => UserProfilesCompanion.insert(
                id: id,
                publicKey: publicKey,
                reputation: reputation,
                badges: badges,
                lastActive: lastActive,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserProfilesTableProcessedTableManager =
    ProcessedTableManager<
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
        BaseReferences<_$AppDatabase, $UserProfilesTable, UserProfile>,
      ),
      UserProfile,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ContentManifestsTableTableManager get contentManifests =>
      $$ContentManifestsTableTableManager(_db, _db.contentManifests);
  $$ContentVersionsTableTableManager get contentVersions =>
      $$ContentVersionsTableTableManager(_db, _db.contentVersions);
  $$HonorValidationsTableTableManager get honorValidations =>
      $$HonorValidationsTableTableManager(_db, _db.honorValidations);
  $$UserProfilesTableTableManager get userProfiles =>
      $$UserProfilesTableTableManager(_db, _db.userProfiles);
}
