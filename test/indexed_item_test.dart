import 'package:flutter_test/flutter_test.dart';
import 'package:offline_accessible_retrieval/src/models/indexed_item.dart';

void main() {
  test('serializes and restores indexed item metadata', () {
    final modifiedAt = DateTime.utc(2026, 6, 25, 12);
    final item = IndexedItem(
      id: 'abc',
      path: '/local/file.txt',
      name: 'file.txt',
      kind: ContentKind.text,
      mimeType: 'text/plain',
      extractedText: 'offline retrieval',
      embedding: const [0.1, 0.2, 0.3],
      modifiedAt: modifiedAt,
    );

    final restored =
        IndexedItem.fromMetadata(item.toMetadata(), item.embedding);

    expect(restored.id, 'abc');
    expect(restored.path, '/local/file.txt');
    expect(restored.kind, ContentKind.text);
    expect(restored.extractedText, 'offline retrieval');
    expect(restored.modifiedAt, modifiedAt);
    expect(restored.embedding, [0.1, 0.2, 0.3]);
  });

  test('restores missing extracted text as empty string', () {
    final metadata = {
      'id': 'abc',
      'path': '/local/file.pdf',
      'name': 'file.pdf',
      'kind': 'document',
      'mimeType': 'application/pdf',
      'modifiedAt': DateTime.utc(2026).toIso8601String(),
    };

    final restored = IndexedItem.fromMetadata(metadata, const [1]);

    expect(restored.kind, ContentKind.document);
    expect(restored.extractedText, isEmpty);
  });
}
