import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_accessible_retrieval/src/embedding/tflite_embedding_engine.dart';
import 'package:offline_accessible_retrieval/src/models/indexed_item.dart';
import 'package:offline_accessible_retrieval/src/models/search_result.dart';
import 'package:offline_accessible_retrieval/src/parsing/local_content_parser.dart';
import 'package:offline_accessible_retrieval/src/retrieval/retrieval_service.dart';
import 'package:offline_accessible_retrieval/src/storage/chroma_vector_store.dart';

void main() {
  test('ingests parsed content into Chroma with embeddings', () async {
    final store = _FakeVectorStore();
    final service = RetrievalService(
      parser: _FakeParser(),
      embeddingEngine: _FakeEmbeddingEngine(const [0.4, 0.5]),
      vectorStore: store,
    );

    final item = await service.ingest(File('/tmp/source.txt'));

    expect(item.id, 'parsed-id');
    expect(item.extractedText, 'parsed text');
    expect(item.embedding, [0.4, 0.5]);
    expect(store.upserted.single.name, 'source.txt');
  });

  test('search embeds the query and delegates to Chroma', () async {
    final store = _FakeVectorStore();
    final service = RetrievalService(
      parser: _FakeParser(),
      embeddingEngine: _FakeEmbeddingEngine(const [0.8, 0.9]),
      vectorStore: store,
    );

    final results = await service.search('find local notes');

    expect(store.lastQueryEmbedding, [0.8, 0.9]);
    expect(results.single.snippet, 'matched note');
  });

  test('search reranks vector results with keyword overlap', () async {
    final store = _FakeVectorStore(results: [
      _result('semantic', 'general semantic match', 0.90),
      _result('keyword', 'local notes retrieval exact match', 0.80),
    ]);
    final service = RetrievalService(
      parser: _FakeParser(),
      embeddingEngine: _FakeEmbeddingEngine(const [0.8, 0.9]),
      vectorStore: store,
    );

    final results = await service.search('local notes retrieval');

    expect(results.first.item.id, 'keyword');
  });
}

class _FakeParser extends LocalContentParser {
  @override
  Future<ParsedContent> parse(File file) async {
    return ParsedContent(
      id: 'parsed-id',
      path: file.path,
      name: 'source.txt',
      kind: ContentKind.text,
      mimeType: 'text/plain',
      text: 'parsed text',
      imageFeatures: const <double>[],
      modifiedAt: DateTime.utc(2026),
    );
  }
}

class _FakeEmbeddingEngine extends TfliteEmbeddingEngine {
  _FakeEmbeddingEngine(this.vector);

  final List<double> vector;

  @override
  Future<List<double>> embed(ParsedContent content) async {
    return vector;
  }

  @override
  Future<List<double>> embedQuery(String text) async {
    return vector;
  }
}

class _FakeVectorStore extends ChromaVectorStore {
  _FakeVectorStore({List<SearchResult>? results})
      : results = results ?? [_result('result-id', 'matched note', 0.99)];

  final List<SearchResult> results;
  final upserted = <IndexedItem>[];
  List<double>? lastQueryEmbedding;

  @override
  Future<void> upsert(IndexedItem item) async {
    upserted.add(item);
  }

  @override
  Future<List<SearchResult>> query(List<double> embedding,
      {int limit = 10}) async {
    lastQueryEmbedding = embedding;
    return results;
  }
}

SearchResult _result(String id, String text, double score) {
  return SearchResult(
    item: IndexedItem(
      id: id,
      path: '/tmp/$id.txt',
      name: '$id.txt',
      kind: ContentKind.text,
      mimeType: 'text/plain',
      extractedText: text,
      embedding: const [0.1, 0.2],
      modifiedAt: DateTime.utc(2026),
    ),
    score: score,
    snippet: text,
  );
}
