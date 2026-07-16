import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/indexed_item.dart';
import '../models/search_result.dart';

class ChromaVectorStore {
  ChromaVectorStore({
    this.baseUrl = 'http://127.0.0.1:8000',
    this.collectionName = 'local_content',
  });

  final String baseUrl;
  final String collectionName;

  Future<void> ensureCollection() async {
    await http.post(
      Uri.parse('$baseUrl/api/v1/collections'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'name': collectionName}),
    );
  }

  Future<void> upsert(IndexedItem item) async {
    await ensureCollection();
    final collection = await _collectionId();
    await http.post(
      Uri.parse('$baseUrl/api/v1/collections/$collection/upsert'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'ids': [item.id],
        'embeddings': [item.embedding],
        'metadatas': [item.toMetadata()],
        'documents': [item.extractedText],
      }),
    );
  }

  Future<List<SearchResult>> query(List<double> embedding,
      {int limit = 10}) async {
    final collection = await _collectionId();
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/collections/$collection/query'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'query_embeddings': [embedding],
        'n_results': limit,
        'include': ['metadatas', 'distances', 'embeddings', 'documents'],
      }),
    );
    if (response.statusCode >= 400) {
      throw StateError('Chroma query failed: ${response.body}');
    }
    final decoded = jsonDecode(response.body) as Map<String, Object?>;
    final metadatas = (decoded['metadatas'] as List).first as List;
    final distances = (decoded['distances'] as List).first as List;
    final embeddings = (decoded['embeddings'] as List).first as List;
    return [
      for (var i = 0; i < metadatas.length; i++)
        SearchResult(
          item: IndexedItem.fromMetadata(
            Map<String, Object?>.from(metadatas[i] as Map),
            List<double>.from((embeddings[i] as List)
                .map((value) => value as num)
                .map((value) => value.toDouble())),
          ),
          score: 1 - (distances[i] as num).toDouble(),
          snippet: _snippet(
              (metadatas[i] as Map)['extractedText']?.toString() ?? ''),
        ),
    ];
  }

  String _snippet(String text) {
    if (text.length <= 120) return text;
    return text.substring(0, 120);
  }

  Future<String> _collectionId() async {
    final response = await http.get(Uri.parse('$baseUrl/api/v1/collections'));
    if (response.statusCode >= 400) {
      throw StateError('Chroma collection lookup failed: ${response.body}');
    }
    final collections = jsonDecode(response.body) as List;
    final collection = collections.cast<Map>().firstWhere(
          (entry) => entry['name'] == collectionName,
          orElse: () =>
              throw StateError('Collection $collectionName not found'),
        );
    return collection['id'] as String;
  }
}
