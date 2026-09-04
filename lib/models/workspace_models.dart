import 'package:flutter/foundation.dart';

@immutable
class Workspace {
  final String id;
  final String name;
  final int pendingTasks;

  const Workspace({
    required this.id,
    required this.name,
    this.pendingTasks = 0,
  });
}

@immutable
class ActivityEvent {
  final String title;
  final String description;
  final DateTime timestamp;

  const ActivityEvent({
    required this.title,
    required this.description,
    required this.timestamp,
  });
}

enum IngestionStatus { pending, processing, completed, error, conflict }

@immutable
class IngestionItem {
  final String id;
  final String filename;
  final double progress;
  final IngestionStatus status;
  final String? conflictMessage;

  const IngestionItem({
    required this.id,
    required this.filename,
    required this.progress,
    required this.status,
    this.conflictMessage,
  });

  IngestionItem copyWith({
    String? id,
    String? filename,
    double? progress,
    IngestionStatus? status,
    String? conflictMessage,
  }) {
    return IngestionItem(
      id: id ?? this.id,
      filename: filename ?? this.filename,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      conflictMessage: conflictMessage ?? this.conflictMessage,
    );
  }
}

@immutable
class IngestionState {
  final double overallProgress;
  final String statusMessage;
  final List<IngestionItem> queue;

  const IngestionState({
    this.overallProgress = 0.0,
    this.statusMessage = '',
    this.queue = const [],
  });

  IngestionState copyWith({
    double? overallProgress,
    String? statusMessage,
    List<IngestionItem>? queue,
  }) {
    return IngestionState(
      overallProgress: overallProgress ?? this.overallProgress,
      statusMessage: statusMessage ?? this.statusMessage,
      queue: queue ?? this.queue,
    );
  }
}

enum NoteStatus { draft, saved, modified, committed }

extension NoteStatusX on NoteStatus {
  String get label {
    switch (this) {
      case NoteStatus.draft:
        return 'Draft';
      case NoteStatus.saved:
        return 'Saved';
      case NoteStatus.modified:
        return 'Modified';
      case NoteStatus.committed:
        return 'Committed';
    }
  }
}

@immutable
class Note {
  final String id;
  final String title;
  final String author;
  final List<String> tags;
  final String summary;
  final String content;
  final NoteStatus status;

  const Note({
    required this.id,
    required this.title,
    required this.author,
    required this.tags,
    required this.summary,
    required this.content,
    this.status = NoteStatus.draft,
  });

  Note copyWith({
    String? id,
    String? title,
    String? author,
    List<String>? tags,
    String? summary,
    String? content,
    NoteStatus? status,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      tags: tags ?? this.tags,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      status: status ?? this.status,
    );
  }
}

@immutable
class Annotation {
  final String id;
  final String docId;
  final String text;
  final String? quote;
  final String author;
  final DateTime createdAt;

  const Annotation({
    required this.id,
    required this.docId,
    required this.text,
    this.quote,
    this.author = 'Reader',
    required this.createdAt,
  });

  Annotation copyWith({
    String? id,
    String? docId,
    String? text,
    String? quote,
    String? author,
    DateTime? createdAt,
  }) {
    return Annotation(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      text: text ?? this.text,
      quote: quote ?? this.quote,
      author: author ?? this.author,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
