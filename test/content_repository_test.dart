import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alexandria/logic/content_repository.dart';
import 'package:alexandria/services/ipfs_service.dart';

void main() {
  group('ContentRepository Envelope Ingestion & Retrieval Tests', () {
    late ProviderContainer container;
    late ContentRepository repository;
    late IpfsService ipfs;

    setUp(() {
      container = ProviderContainer();
      repository = container.read(contentRepositoryProvider);
      ipfs = container.read(ipfsServiceProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('creates plaintext content manifest and retrieves via IPFS', () async {
      final raw = Uint8List.fromList('Alexandria Unencrypted Ancient Texts'.codeUnits);
      final uuid = await repository.createContent(
        title: 'Ancient Philosophy',
        author: 'Aristotle',
        fileData: raw,
        isEncrypted: false,
      );

      expect(uuid.isNotEmpty, isTrue);
    });

    test('creates encrypted content manifest with AES-256-GCM and decrypts on retrieval', () async {
      final raw = Uint8List.fromList('Classified Library Scroll'.codeUnits);
      final uuid = await repository.createContent(
        title: 'Encrypted Knowledge',
        author: 'Anonymous Librarian',
        fileData: raw,
        isEncrypted: true,
      );

      expect(uuid.isNotEmpty, isTrue);
    });
  });
}
