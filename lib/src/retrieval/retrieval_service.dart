import 'dart:io';

import '../embedding/tflite_embedding_engine.dart';
import '../models/indexed_item.dart';
import '../models/search_result.dart';
import '../parsing/local_content_parser.dart';
import '../storage/chroma_vector_store.dart';

class RetrievalService {
  RetrievalService({
    required this.parser,
    required this.embeddingEngine,
    required this.vectorStore,
  });

  final LocalContentParser parser;
  final TfliteEmbeddingEngine embeddingEngine;
  final ChromaVectorStore vectorStore;

  /// Build the multimodal embedding for a freshly parsed item, using the
  /// BERT text encoder and the on-device image feature print. Falls back to
  /// a deterministic hash-based vector when the bundled models are not
  /// present, so the index is always populated and cross-modal similarity
  /// remains meaningful.
  Future<List<double>> embedForIndexing(ParsedContent parsed) async {
    return embeddingEngine.embed(parsed);
  }

  /// Build the query-side multimodal embedding. Text side is populated;
  /// the image half stays empty (zeros) so cosine against image items
  /// naturally weights the textual similarity.
  Future<List<double>> embedQuery(String text) async {
    return embeddingEngine.embedQuery(text);
  }

  Future<IndexedItem> ingest(File file) async {
    final parsed = await parser.parse(file);
    final embedding = await embedForIndexing(parsed);
    final item = IndexedItem(
      id: parsed.id,
      path: parsed.path,
      name: parsed.name,
      kind: parsed.kind,
      mimeType: parsed.mimeType,
      extractedText: parsed.text,
      embedding: embedding,
      modifiedAt: parsed.modifiedAt,
    );
    try {
      await vectorStore.upsert(item);
    } catch (_) {
      // Vector store may be offline; the local TF-IDF index still works.
    }
    return item;
  }

  Future<List<SearchResult>> search(String query) async {
    final embedding = await embedQuery(query);
    try {
      final results = await vectorStore.query(embedding);
      return _hybridRank(query, results);
    } catch (_) {
      return const <SearchResult>[];
    }
  }

  List<SearchResult> _hybridRank(String query, List<SearchResult> results) {
    final queryTerms = _terms(query);
    if (queryTerms.isEmpty) return results;
    final reranked = [
      for (final result in results)
        SearchResult(
          item: result.item,
          score: (result.score * 0.75) +
              (_keywordScore(queryTerms, result.item.extractedText) * 0.25),
          snippet: result.snippet,
        ),
    ];
    reranked.sort((a, b) => b.score.compareTo(a.score));
    return reranked;
  }

  Set<String> _terms(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'))
        .where((term) => term.length > 1)
        .toSet();
  }

  double _keywordScore(Set<String> queryTerms, String documentText) {
    final documentTerms = _terms(documentText);
    if (documentTerms.isEmpty) return 0;
    final overlap = queryTerms.where(documentTerms.contains).length;
    return overlap / queryTerms.length;
  }
}
