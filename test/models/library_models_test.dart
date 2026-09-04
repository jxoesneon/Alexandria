import 'package:alexandria/models/library_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LibraryStats', () {
    const stats = LibraryStats(
      totalItems: 5,
      totalSize: '1.2 MB',
      networkStatus: 'Synchronized',
    );

    test('stores all fields', () {
      expect(stats.totalItems, 5);
      expect(stats.totalSize, '1.2 MB');
      expect(stats.networkStatus, 'Synchronized');
    });
  });

  group('LibraryItem', () {
    const item = LibraryItem(
      cid: 'cid-1',
      title: 'The Great Gatsby',
      author: 'F. Scott Fitzgerald',
    );

    test('default progress is 0.0', () {
      expect(item.progress, 0.0);
    });

    test('progress can be specified', () {
      const itemWithProgress = LibraryItem(
        cid: 'cid-1',
        title: 'The Great Gatsby',
        author: 'F. Scott Fitzgerald',
        progress: 0.75,
      );
      expect(itemWithProgress.progress, 0.75);
    });
  });

  group('SearchResult', () {
    final now = DateTime(2024, 1, 1);
    final result = SearchResult(
      id: 'id-1',
      title: 'Search Title',
      author: 'Search Author',
      format: 'epub',
      dateAdded: now,
    );

    test('stores all fields', () {
      expect(result.id, 'id-1');
      expect(result.title, 'Search Title');
      expect(result.author, 'Search Author');
      expect(result.format, 'epub');
      expect(result.dateAdded, now);
    });
  });

  group('DocumentStream', () {
    const document = DocumentStream(
      title: 'Decentralized Web',
      content: 'A deep dive into distributed archives.',
    );

    test('stores title and content', () {
      expect(document.title, 'Decentralized Web');
      expect(document.content, 'A deep dive into distributed archives.');
    });
  });

  group('Annotation', () {
    const annotation = Annotation(text: 'A useful note');

    test('stores text', () {
      expect(annotation.text, 'A useful note');
    });
  });

  group('CollectionNode', () {
    const node = CollectionNode(id: 'n1', name: 'Node 1');

    test('children default to an empty list', () {
      expect(node.children, isEmpty);
    });

    test('stores id, name and children', () {
      const child = CollectionNode(id: 'c1', name: 'Child');
      const parent = CollectionNode(
        id: 'p1',
        name: 'Parent',
        children: [child],
      );

      expect(parent.id, 'p1');
      expect(parent.name, 'Parent');
      expect(parent.children, [child]);
    });
  });

  group('CollectionItem', () {
    const item = CollectionItem(
      id: 'i1',
      title: 'Item Title',
      author: 'Item Author',
      format: 'PDF',
    );

    test('stores all fields', () {
      expect(item.id, 'i1');
      expect(item.title, 'Item Title');
      expect(item.author, 'Item Author');
      expect(item.format, 'PDF');
    });
  });
}
