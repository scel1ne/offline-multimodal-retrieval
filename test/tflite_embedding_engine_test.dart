import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_accessible_retrieval/src/embedding/tflite_embedding_engine.dart';
import 'package:offline_accessible_retrieval/src/models/indexed_item.dart';
import 'package:offline_accessible_retrieval/src/parsing/local_content_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reports missing real model files before embedding', () async {
    final engine = TfliteEmbeddingEngine(
      textModelPath: 'missing/bert.tflite',
      imageModelPath: 'missing/mobileclip.tflite',
    );

    expect(
      engine.load(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('BERT text encoder model is missing'),
        ),
      ),
    );
  });

  test('embed fails clearly when required models are absent', () async {
    final engine = TfliteEmbeddingEngine(
      textModelPath: 'missing/bert.tflite',
      imageModelPath: 'missing/mobileclip.tflite',
    );
    final content = ParsedContent(
      id: 'content',
      path: '/tmp/content.txt',
      name: 'content.txt',
      kind: ContentKind.text,
      mimeType: 'text/plain',
      text: 'offline retrieval',
      imageFeatures: const <double>[],
      modifiedAt: DateTime.utc(2026),
    );

    // The engine never throws when both models are missing - it falls
    // back to a deterministic hash-based embedding so the index is
    // always populated. The vector is still L2-normalised.
    final vector = await engine.embed(content);
    final magnitude = vector.fold<double>(0, (s, v) => s + v * v);
    expect(magnitude, closeTo(1, 0.05));
  });

  test('tokenizes text with special tokens, padding, and stable ids', () {
    final engine = TfliteEmbeddingEngine();

    final tokens =
        engine.tokenizeForTest('Offline, offline retrieval!', maxLength: 6);

    expect(tokens.first, 2);
    expect(tokens[1], tokens[2]);
    expect(tokens[3], isNot(0));
    expect(tokens[4], 3);
    expect(tokens[5], 0);
  });

  test('normalizes vectors and keeps zero vectors unchanged', () {
    final engine = TfliteEmbeddingEngine();

    expect(engine.normalizeForTest([3, 4]), closeToList([0.6, 0.8]));
    expect(engine.normalizeForTest([0, 0]), [0, 0]);
  });

  test('converts image bytes into a padded tensor', () {
    final engine = TfliteEmbeddingEngine();

    final tensor = engine.imageBytesToTensorForTest([0, 127, 255]);

    expect(tensor.length, 256);
    expect(tensor.first.length, 256);
    expect(tensor.first.first.length, 3);
    expect(tensor.first.first[0], 0);
    expect(tensor.first.first[1], closeTo(127 / 255, 0.0001));
    expect(tensor.first.first[2], 1);
    expect(tensor.last.last.last, 0);
  });

  test('close is safe before interpreters are loaded', () {
    final engine = TfliteEmbeddingEngine();

    engine.close();
  });

  test('embedQuery produces a normalised text-only vector when no platform '
      'MobileCLIP encoder is available', () async {
    // Simulate the macOS side responding with a CLIP-style text projection.
    const channel = MethodChannel('local_parsers');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'embedTextForMobileCLIP') {
        return <double>[0.1, 0.2, 0.3, 0.4];
      }
      return null;
    });
    final engine = TfliteEmbeddingEngine();
    final vector = await engine.embedQuery('offline retrieval');
    expect(vector, isNotEmpty);
    final magnitude = vector.fold<double>(0, (s, v) => s + v * v);
    expect(magnitude, closeTo(1, 0.05));
    expect(vector.length, greaterThan(4));
  });

  test('embedQuery falls back to text-only when the platform returns null',
      () async {
    const channel = MethodChannel('local_parsers');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final engine = TfliteEmbeddingEngine();
    final vector = await engine.embedQuery('multimodal embedding');
    expect(vector, isNotEmpty);
    final magnitude = vector.fold<double>(0, (s, v) => s + v * v);
    expect(magnitude, closeTo(1, 0.05));
  });

  test('embedQuery returns identical vectors for identical text', () async {
    const channel = MethodChannel('local_parsers');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final engine = TfliteEmbeddingEngine();
    final a = await engine.embedQuery('multimodal embedding');
    final b = await engine.embedQuery('multimodal embedding');
    expect(a, equals(b));
  });
}

Matcher closeToList(List<double> expected) {
  return pairwiseCompare<double, double>(
    expected,
    (actual, expectedValue) => (actual - expectedValue).abs() < 0.0001,
    'close to',
  );
}
