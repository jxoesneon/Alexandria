/// View models used by the Library screens.
///
/// These are intentionally lightweight transformation objects; the underlying
/// data comes from the real services (database, content repository,
/// collection service, etc.).
class LibraryStats {
  final int totalItems;
  final String totalSize;
  final String networkStatus;

  const LibraryStats({
    required this.totalItems,
    required this.totalSize,
    required this.networkStatus,
  });
}

class LibraryItem {
  final String cid;
  final String title;
  final String author;
  final double progress;

  const LibraryItem({
    required this.cid,
    required this.title,
    required this.author,
    this.progress = 0.0,
  });
}

class SearchResult {
  final String id;
  final String title;
  final String author;
  final String format;
  final DateTime dateAdded;

  SearchResult({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
    required this.dateAdded,
  });
}

class DocumentStream {
  final String title;
  final String content;

  const DocumentStream({required this.title, required this.content});
}

class Annotation {
  final String text;

  const Annotation({required this.text});
}

class CollectionNode {
  final String id;
  final String name;
  final List<CollectionNode> children;

  const CollectionNode({
    required this.id,
    required this.name,
    this.children = const [],
  });
}

class CollectionItem {
  final String id;
  final String title;
  final String author;
  final String format;

  const CollectionItem({
    required this.id,
    required this.title,
    required this.author,
    required this.format,
  });
}
