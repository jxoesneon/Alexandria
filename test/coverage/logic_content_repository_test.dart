import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/data/database.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/models/workspace_models.dart';

void main() {
  late ProviderContainer container;
  late ContentRepository repo;

  setUp(() {
    // The global harness mock returns null for every read; install a
    // stateful in-memory store so the DEK round-trip path is exercisable.
    final store = <String, String>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final key = call.arguments['key'] as String?;
        switch (call.method) {
          case 'read':
            return store[key];
          case 'write':
            store[key!] = call.arguments['value'] as String;
            return null;
          case 'delete':
            store.remove(key);
            return null;
          case 'containsKey':
            return store.containsKey(key);
          default:
            return null;
        }
      },
    );
    container = ProviderContainer();
    repo = container.read(contentRepositoryProvider);
  });

  tearDown(() {
    container.dispose();
  });

  /// Pull the version rows for a manifest uuid via the database.
  Future<List<ContentVersion>> versionsFor(String uuid) async {
    final db = container.read(databaseProvider);
    final manifest = await repo.getManifestByUuid(uuid);
    if (manifest == null) return const [];
    return db.getVersionsForManifest(manifest.id);
  }

  group('createContent / retrieveContent', () {
    test('plaintext round-trip stores manifest and returns bytes', () async {
      final data = utf8.encode('hello world plaintext payload');
      final uuid = await repo.createContent(
        title: 'Plain Doc',
        author: 'Alice',
        description: 'a description',
        fileData: data,
        tags: const ['a', 'b'],
        category: 'docs',
        format: 'txt',
        extraMetadata: const {'k': 'v'},
      );

      final manifest = await repo.getManifestByUuid(uuid);
      expect(manifest, isNotNull);
      expect(manifest!.title, 'Plain Doc');
      expect(manifest.category, 'docs');
      expect(manifest.isEncrypted, isFalse);
      expect(manifest.encryptionKey, isNull);

      final versions = await versionsFor(uuid);
      expect(versions, isNotEmpty);
      final cid = versions.first.cid;
      final fetched = await repo.retrieveContent(cid);
      expect(utf8.decode(fetched), 'hello world plaintext payload');
    });

    test('encrypted round-trip stores DEK in secure storage only', () async {
      final data = utf8.encode('secret payload that must be encrypted');
      final uuid = await repo.createContent(
        title: 'Secret Doc',
        fileData: data,
        isEncrypted: true,
      );

      final manifest = await repo.getManifestByUuid(uuid);
      expect(manifest, isNotNull);
      expect(manifest!.isEncrypted, isTrue);
      // The manifest row must never carry usable key material.
      expect(manifest.encryptionKey, isNull);

      final dek = await repo.contentDekBase64(uuid);
      expect(dek, isNotNull);

      final versions = await versionsFor(uuid);
      expect(versions, isNotEmpty);
      final cid = versions.first.cid;

      // Ciphertext is content-addressed; retrieving without the DEK yields
      // ciphertext bytes (hash still verifies against the CID).
      final raw = await repo.retrieveContent(cid);
      expect(raw, isNot(equals(data)));

      // With the DEK we recover the plaintext.
      final plain = await repo.retrieveManifestContent(uuid, cid);
      expect(utf8.decode(plain), 'secret payload that must be encrypted');
    });

    test('unknown CID fails the integrity check', () async {
      // A structurally plausible but nonexistent CID has no payload, so the
      // empty-bytes integrity gate must throw.
      await expectLater(
        () => repo.retrieveContent('bafkreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
        throwsStateError,
      );
    });

    test('wrong DEK fails the AEAD check', () async {
      final data = utf8.encode('payload for wrong-key test' * 4);
      final uuid = await repo.createContent(
        title: 'Keyed',
        fileData: data,
        isEncrypted: true,
      );
      final versions = await versionsFor(uuid);
      final cid = versions.first.cid;
      final wrongKey = base64Encode(List<int>.filled(32, 7));
      await expectLater(
        () => repo.retrieveContent(cid, dekBase64: wrongKey),
        throwsStateError,
      );
    });
  });

  group('paging and versioning', () {
    test('getContentPage returns empty page beyond bounds', () async {
      final page = await repo.getContentPage(page: 9, pageSize: 10);
      expect(page, isEmpty);
    });

    test('addVersion is a no-op for unknown uuid', () async {
      await repo.addVersion('nonexistent-uuid', 'cid-x', 'en', 'txt');
    });

    test('addVersion inserts a row for a known manifest', () async {
      final uuid = await repo.createContent(
        title: 'V',
        fileData: utf8.encode('versionable content payload' * 3),
      );
      await repo.addVersion(uuid, 'cid-manual', 'fr', 'epub', sizeBytes: 5);
      final versions = await versionsFor(uuid);
      expect(versions.length, 2);
      expect(versions.any((v) => v.cid == 'cid-manual'), isTrue);
    });

    test('versionSigningPayload binds uuid and cid', () {
      final payload =
          utf8.decode(ContentRepository.versionSigningPayload('u1', 'c1'));
      expect(payload, 'alexandria:version:v1:u1:c1');
    });

    test('addContentVersion rejects payload below minimum size', () async {
      await expectLater(
        () => repo.addContentVersion(
            manifestUuid: 'x', fileData: utf8.encode('tiny')),
        throwsArgumentError,
      );
    });

    test('addContentVersion rejects missing manifest', () async {
      await expectLater(
        () => repo.addContentVersion(
            manifestUuid: 'missing', fileData: utf8.encode('x' * 100)),
        throwsArgumentError,
      );
    });

    test('addContentVersion inserts and flags fragment-of-ancestor', () async {
      final base = Uint8List.fromList(List<int>.generate(256, (i) => i % 97));
      final uuid = await repo.createContent(
        title: 'Frag',
        fileData: base,
      );
      // A sub-sequence of the original payload must be flagged.
      final fragment = Uint8List.fromList(base.sublist(10, 120));
      final cid = await repo.addContentVersion(
          manifestUuid: uuid, fileData: fragment, format: 'bin');
      expect(cid, isNotEmpty);
      final versions = await versionsFor(uuid);
      final flagged = versions
          .where((v) => v.flaggedReason != null)
          .map((v) => v.flaggedReason!);
      expect(flagged, isNotEmpty);
      expect(flagged.first, startsWith('suspect-fragment-of:'));
    });
  });

  group('integrity probe', () {
    test('probeContentIntegrity reports hash and unsigned signature', () async {
      final uuid = await repo.createContent(
        title: 'Probe',
        fileData: utf8.encode('probe me ' * 20),
      );
      final versions = await versionsFor(uuid);
      final cid = versions.first.cid;
      final report = await repo.probeContentIntegrity(cid);
      expect(report.cid, cid);
      expect(report.payloadHashOk, isTrue);
    });

    test('probeContentIntegrity for unknown cid reports hash failure',
        () async {
      final report = await repo
          .probeContentIntegrity('bafkreiaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(report.payloadHashOk, isFalse);
      expect(report.signatureValid, isNull);
    });
  });

  group('notes and annotations', () {
    test('saveNote creates then updates a note manifest', () async {
      const note = Note(
        id: 'note-1',
        title: 'My Note',
        author: 'Bob',
        tags: ['t1'],
        summary: 'sum',
        content: '# Body',
        status: NoteStatus.draft,
      );
      await repo.saveNote(note);
      var fetched = await repo.getNoteByUuid('note-1');
      expect(fetched.title, 'My Note');
      expect(fetched.content, '# Body');
      expect(fetched.status, NoteStatus.draft);

      const updated = Note(
        id: 'note-1',
        title: 'My Note 2',
        author: '',
        tags: [],
        summary: '',
        content: 'edited',
        status: NoteStatus.modified,
      );
      await repo.saveNote(updated);
      fetched = await repo.getNoteByUuid('note-1');
      expect(fetched.title, 'My Note 2');
      expect(fetched.content, 'edited');
      expect(fetched.status, NoteStatus.modified);
    });

    test('commitNote persists a version and returns a CID', () async {
      const note = Note(
        id: 'note-2',
        title: 'Commit Me',
        author: 'a',
        tags: [],
        summary: '',
        content: 'committed body',
        status: NoteStatus.committed,
      );
      final cid = await repo.commitNote(note);
      expect(cid, isNotEmpty);
      final manifest = await repo.getManifestByUuid('note-2');
      expect(manifest, isNotNull);
    });

    test('addAnnotation + watchAnnotations round-trip', () async {
      const note = Note(
        id: 'doc-ann',
        title: 'Doc',
        author: '',
        tags: [],
        summary: '',
        content: 'body',
      );
      await repo.saveNote(note);
      await repo.addAnnotation(
        'doc-ann',
        Annotation(
          id: 'ann-1',
          docId: 'doc-ann',
          text: 'note text',
          quote: 'quoted',
          author: 'Carol',
          createdAt: DateTime(2024, 1, 1),
        ),
      );
      final annotations = await repo.watchAnnotations('doc-ann').first;
      expect(annotations, hasLength(1));
      expect(annotations.first.text, 'note text');
      expect(annotations.first.quote, 'quoted');
      expect(annotations.first.author, 'Carol');
    });

    test('watchAnnotations is empty for unknown doc', () async {
      final annotations = await repo.watchAnnotations('nope').first;
      expect(annotations, isEmpty);
    });
  });

  group('plugin capability view', () {
    test('read-only capability refuses writes and key material', () async {
      final cap = repo.asPluginCapability(canWrite: false);

      await expectLater(
        () => cap.createContent(title: 'x', fileData: utf8.encode('y')),
        throwsStateError,
      );
      await expectLater(
        () => cap.addVersion('u', 'c', 'en', 'txt'),
        throwsStateError,
      );
      await expectLater(
        () => cap.saveNote(const Note(
            id: 'n',
            title: 't',
            author: '',
            tags: [],
            summary: '',
            content: '')),
        throwsStateError,
      );

      // Key material is never a plugin capability.
      expect(await cap.contentDekBase64('any'), isNull);
      await expectLater(
        () => cap.retrieveManifestContent('u', 'c'),
        throwsStateError,
      );
    });

    test('capability projects manifests without encryptionKey', () async {
      final uuid = await repo.createContent(
        title: 'Projected',
        fileData: utf8.encode('data ' * 40),
        isEncrypted: true,
      );
      final cap = repo.asPluginCapability(canWrite: true);
      final manifest = await cap.getManifestByUuid(uuid);
      expect(manifest, isNotNull);
      expect(manifest!.encryptionKey, isNull);
      final all = await cap.getAllManifests();
      expect(all.every((m) => m.encryptionKey == null), isTrue);
      final page = await cap.getContentPage(page: 0, pageSize: 50);
      expect(page.every((m) => m.encryptionKey == null), isTrue);
    });
  });
}
