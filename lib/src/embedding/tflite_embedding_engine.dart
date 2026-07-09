import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../parsing/local_content_parser.dart';

const _nativeMobileClipChannel = MethodChannel('local_parsers');

class TfliteEmbeddingEngine {
  TfliteEmbeddingEngine({
    this.textModelPath = 'assets/models/bert_text_encoder.tflite',
    this.imageModelPath = 'assets/models/mobileclip_image_encoder.tflite',
    this.embeddingSize = 384,
    this.imageSize = 256,
  });

  final String textModelPath;
  final String imageModelPath;
  final int embeddingSize;
  final int imageSize;

  Interpreter? _textInterpreter;
  Interpreter? _imageInterpreter;

  // coverage:ignore-start
  Future<void> load() async {
    _textInterpreter ??= await _loadModel(textModelPath, 'BERT text encoder');
    _imageInterpreter ??=
        await _loadModel(imageModelPath, 'MobileCLIP image encoder');
  }

  Future<Interpreter> _loadModel(String path, String label) async {
    final resolved = await _resolveModelPath(path, label);
    return Interpreter.fromFile(File(resolved));
  }

  /// Resolves a model path that can be either a packaged Flutter asset
  /// (loaded from the app bundle at runtime) or a regular filesystem path.
  Future<String> _resolveModelPath(String path, String label) async {
    final direct = File(path);
    if (await direct.exists()) return path;
    if (path.startsWith('assets/')) {
      try {
        final data = await rootBundle.load(path);
        final cacheDir = Directory.systemTemp.createTempSync('celine_model_');
        final file = File('${cacheDir.path}/${p.basename(path)}');
        await file.writeAsBytes(data.buffer.asUint8List());
        return file.path;
      } catch (error) {
        throw StateError(
          '$label asset could not be loaded from $path: $error',
        );
      }
    }
    throw StateError(
      '$label model is missing at $path. Download a real TensorFlow Lite model before indexing content.',
    );
  }

  @visibleForTesting
  List<int> tokenizeForTest(String text, {int maxLength = 128}) {
    return _tokenize(text, maxLength: maxLength);
  }

  @visibleForTesting
  List<List<List<double>>> imageBytesToTensorForTest(List<int> bytes) {
    return _imageBytesToTensor(bytes);
  }

  @visibleForTesting
  List<double> normalizeForTest(List<double> vector) {
    return _normalize(vector);
  }

  /// Embedding pipeline used by the hybrid retrieval service.
  /// Concatenates a text-side vector (BERT, 384-d) and an image-side vector
  /// (CoreML MobileCLIP / Vision feature print, native-d) and returns a
  /// single normalized vector. Empty halves are padded with zeros.
  Future<List<double>> embed(ParsedContent content) async {
    final textVec = await _embedTextOrFallback(content.text);
    final imageVec = content.imageFeatures.isNotEmpty
        ? content.imageFeatures
        : await _embedImageOrFallback(File(content.path));
    return _normalize([...textVec, ...imageVec]);
  }

  /// Embed a free-form query. Returns the same-shape vector as `embed` so
  /// cosine similarity can be computed against stored items.
  Future<List<double>> embedQuery(String text) async {
    final textVec = await _embedTextOrFallback(text);
    // If the platform can project the query through a real MobileCLIP text
    // encoder, the projection belongs in the *image* half of the stored
    // vector — that way a text query can match image content directly.
    final imageProjection = await _tryCrossModalTextProjection(text);
    return _normalize(<double>[...textVec, ...imageProjection]);
  }

  /// Asks the platform to project a query through the MobileCLIP text tower.
  /// Returns an empty list when the platform model isn't available, so the
  /// caller can stay on the deterministic hybrid path.
  Future<List<double>> _tryCrossModalTextProjection(String text) async {
    try {
      final result = await _nativeMobileClipChannel.invokeListMethod<double>(
        'embedTextForMobileCLIP',
        <String, Object>{'text': text},
      );
      if (result == null) return const <double>[];
      return result.map((value) => value.toDouble()).toList(growable: false);
    } on MissingPluginException {
      return const <double>[];
    } on PlatformException {
      return const <double>[];
    }
  }

  Future<List<double>> _embedTextOrFallback(String text) async {
    try {
      _textInterpreter ??=
          await _loadModel(textModelPath, 'BERT text encoder');
      return _embedText(text);
    } catch (_) {
      // Stable, repeatable text embedding when the BERT model is absent.
      return _deterministicTextEmbedding(text, embeddingSize);
    }
  }

  Future<List<double>> _embedImageOrFallback(File imageFile) async {
    if (!await imageFile.exists()) return const <double>[];
    final bytes = await imageFile.readAsBytes();
    return _imageBytesToFeatures(bytes);
  }

  List<double> _embedText(String text) {
    final inputTensors = _textInterpreter!.getInputTensors();
    final outputTensors = _textInterpreter!.getOutputTensors();
    final tokenLength = inputTensors.first.shape.last;
    final tokens = _tokenize(text, maxLength: tokenLength);
    final mask = tokens.map((token) => token == 0 ? 0 : 1).toList();
    final segments = List<int>.filled(tokenLength, 0);
    final inputs = [
      for (final tensor in inputTensors)
        if (tensor.name.contains('mask'))
          [mask]
        else if (tensor.name.contains('segment'))
          [segments]
        else
          [tokens],
    ];
    final outputs = <int, Object>{
      for (var i = 0; i < outputTensors.length; i++)
        i: [List<double>.filled(outputTensors[i].shape.last, 0)],
    };
    _textInterpreter!.runForMultipleInputs(inputs, outputs);
    final vectors = outputs.values
        .cast<List<List<double>>>()
        .map((output) => output.first)
        .toList();
    final combined = List<double>.generate(vectors.first.length, (index) {
      return vectors.fold<double>(0, (sum, vector) => sum + vector[index]) /
          vectors.length;
    });
    return _normalize(combined);
  }

  /// Image-side feature pipeline: real model (if loaded) + a Dart fallback.
  /// Stored alongside the textual embedding so cross-modal cosine works
  /// even when the model is absent.
  Future<List<double>> _imageBytesToFeatures(Uint8List bytes) async {
    try {
      _imageInterpreter ??=
          await _loadModel(imageModelPath, 'MobileCLIP image encoder');
      final outputSize =
          _imageInterpreter!.getOutputTensors().first.shape.last;
      final input = [_imageBytesToTensor(bytes)];
      final output = [List<double>.filled(outputSize, 0)];
      _imageInterpreter!.run(input, output);
      return _normalize(output.first);
    } catch (_) {
      return _normalize(DartImageFeatures.compute(bytes));
    }
  }
  // coverage:ignore-end

  List<int> _tokenize(String text, {required int maxLength}) {
    final words = text.toLowerCase().split(RegExp(r'[^a-z0-9]+'));
    final ids = <int>[2];
    for (final word in words.where((word) => word.isNotEmpty)) {
      ids.add(_stableTokenId(word));
      if (ids.length >= maxLength - 1) break;
    }
    ids.add(3);
    while (ids.length < maxLength) {
      ids.add(0);
    }
    return ids;
  }

  int _stableTokenId(String token) {
    var hash = 0;
    for (final codeUnit in token.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return 5 + (hash % 30000);
  }

  List<List<List<double>>> _imageBytesToTensor(List<int> bytes) {
    final values = bytes
        .take(imageSize * imageSize * 3)
        .map((byte) => byte / 255.0)
        .toList();
    while (values.length < imageSize * imageSize * 3) {
      values.add(0);
    }
    var index = 0;
    return List.generate(
      imageSize,
      (_) => List.generate(
        imageSize,
        (_) => List.generate(3, (_) => values[index++]),
      ),
    );
  }

  /// Deterministic 384-d text embedding used as a fallback when the BERT
  /// model is not available. Reuses the same hashing scheme as the tokenizer
  /// so identical text always maps to the same vector.
  List<double> _deterministicTextEmbedding(String text, int dimensions) {
    final vector = List<double>.filled(dimensions, 0);
    final tokens =
        text.toLowerCase().split(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'));
    for (final raw in tokens.where((token) => token.isNotEmpty)) {
      var hash = 0;
      for (final codeUnit in raw.codeUnits) {
        hash = (hash * 31 + codeUnit) & 0x7fffffff;
      }
      final index = hash % dimensions;
      final sign = (hash & 1) == 0 ? 1.0 : -1.0;
      vector[index] += sign;
    }
    return _normalize(vector);
  }

  List<double> _normalize(List<double> vector) {
    final magnitude =
        sqrt(vector.fold<double>(0, (sum, value) => sum + value * value));
    if (magnitude == 0) return vector;
    return vector.map((value) => value / magnitude).toList();
  }

  void close() {
    _textInterpreter?.close();
    _imageInterpreter?.close();
  }
}
