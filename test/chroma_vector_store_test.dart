import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_accessible_retrieval/src/models/indexed_item.dart';
import 'package:offline_accessible_retrieval/src/storage/chroma_vector_store.dart';

void main() {
  test('upserts and queries through the Chroma HTTP API', () async {
    final requests = <String>[];
    late HttpServer server;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = server.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      request.response.headers.contentType = ContentType.json;

      if (request.method == 'POST' &&
          request.uri.path == '/api/v1/collections') {
        await request.drain<void>();
        request.response
          ..statusCode = 200
          ..write(jsonEncode({'id': 'collection-1'}));
      } else if (request.method == 'GET' &&
          request.uri.path == '/api/v1/collections') {
        request.response
          ..statusCode = 200
          ..write(jsonEncode([
            {'id': 'collection-1', 'name': 'local_content'},
          ]));
      } else if (request.method == 'POST' &&
          request.uri.path == '/api/v1/collections/collection-1/upsert') {
        final body = await utf8.decoder.bind(request).join();
        expect(body, contains('offline retrieval'));
        request.response
          ..statusCode = 200
          ..write(jsonEncode({'ok': true}));
      } else if (request.method == 'POST' &&
          request.uri.path == '/api/v1/collections/collection-1/query') {
        request.response
          ..statusCode = 200
          ..write(jsonEncode({
            'metadatas': [
              [
                {
                  'id': 'abc',
                  'path': '/local/file.txt',
                  'name': 'file.txt',
                  'kind': 'text',
                  'mimeType': 'text/plain',
                  'modifiedAt': DateTime.utc(2026).toIso8601String(),
                  'extractedText': 'offline retrieval result',
                }
              ]
            ],
            'distances': [
              [0.25]
            ],
            'embeddings': [
              [
                [0.1, 0.2]
              ]
            ],
          }));
      } else {
        request.response.statusCode = 404;
      }

      await request.response.close();
    });

    addTearDown(() async {
      await sub.cancel();
      await server.close(force: true);
    });

    final store = ChromaVectorStore(baseUrl: 'http://127.0.0.1:${server.port}');
    final item = IndexedItem(
      id: 'abc',
      path: '/local/file.txt',
      name: 'file.txt',
      kind: ContentKind.text,
      mimeType: 'text/plain',
      extractedText: 'offline retrieval',
      embedding: const [0.1, 0.2],
      modifiedAt: DateTime.utc(2026),
    );

    await store.upsert(item);
    final results = await store.query(const [0.1, 0.2], limit: 1);

    expect(requests, contains('POST /api/v1/collections'));
    expect(requests, contains('POST /api/v1/collections/collection-1/upsert'));
    expect(results.single.item.name, 'file.txt');
    expect(results.single.score, 0.75);
    expect(results.single.snippet, 'offline retrieval result');
  });

  test('truncates long snippets returned from Chroma', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final longText = 'x' * 130;
    final sub = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode([
          {'id': 'collection-1', 'name': 'local_content'},
        ]));
      } else {
        request.response.write(jsonEncode({
          'metadatas': [
            [
              {
                'id': 'abc',
                'path': '/local/file.txt',
                'name': 'file.txt',
                'kind': 'text',
                'mimeType': 'text/plain',
                'modifiedAt': DateTime.utc(2026).toIso8601String(),
                'extractedText': longText,
              }
            ]
          ],
          'distances': [
            [0.1]
          ],
          'embeddings': [
            [
              [0.1, 0.2]
            ]
          ],
        }));
      }
      await request.response.close();
    });

    addTearDown(() async {
      await sub.cancel();
      await server.close(force: true);
    });

    final store = ChromaVectorStore(baseUrl: 'http://127.0.0.1:${server.port}');

    final results = await store.query(const [1], limit: 1);

    expect(results.single.snippet.length, 120);
  });

  test('reports Chroma query failures', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode([
          {'id': 'collection-1', 'name': 'local_content'},
        ]));
      } else {
        request.response
          ..statusCode = 500
          ..write('broken');
      }
      await request.response.close();
    });

    addTearDown(() async {
      await sub.cancel();
      await server.close(force: true);
    });

    final store = ChromaVectorStore(baseUrl: 'http://127.0.0.1:${server.port}');

    expect(store.query(const [1]), throwsA(isA<StateError>()));
  });

  test('reports missing Chroma collections', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<Map<String, Object?>>[]));
      await request.response.close();
    });

    addTearDown(() async {
      await sub.cancel();
      await server.close(force: true);
    });

    final store = ChromaVectorStore(baseUrl: 'http://127.0.0.1:${server.port}');

    expect(store.query(const [1]), throwsA(isA<StateError>()));
  });

  test('reports failed Chroma collection lookups', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = server.listen((request) async {
      request.response
        ..statusCode = 500
        ..write('lookup failed');
      await request.response.close();
    });

    addTearDown(() async {
      await sub.cancel();
      await server.close(force: true);
    });

    final store = ChromaVectorStore(baseUrl: 'http://127.0.0.1:${server.port}');

    expect(store.query(const [1]), throwsA(isA<StateError>()));
  });
}
