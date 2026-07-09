enum ContentKind { text, document, image }

class IndexedItem {
  const IndexedItem({
    required this.id,
    required this.path,
    required this.name,
    required this.kind,
    required this.mimeType,
    required this.extractedText,
    required this.embedding,
    required this.modifiedAt,
  });

  final String id;
  final String path;
  final String name;
  final ContentKind kind;
  final String mimeType;
  final String extractedText;
  final List<double> embedding;
  final DateTime modifiedAt;

  Map<String, Object?> toMetadata() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'kind': kind.name,
      'mimeType': mimeType,
      'modifiedAt': modifiedAt.toIso8601String(),
      'extractedText': extractedText,
    };
  }

  static IndexedItem fromMetadata(
    Map<String, Object?> metadata,
    List<double> embedding,
  ) {
    return IndexedItem(
      id: metadata['id'] as String,
      path: metadata['path'] as String,
      name: metadata['name'] as String,
      kind: ContentKind.values.byName(metadata['kind'] as String),
      mimeType: metadata['mimeType'] as String,
      extractedText: metadata['extractedText'] as String? ?? '',
      modifiedAt: DateTime.parse(metadata['modifiedAt'] as String),
      embedding: embedding,
    );
  }
}
