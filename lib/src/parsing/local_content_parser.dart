import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/indexed_item.dart';

class ParsedContent {
  const ParsedContent({
    required this.id,
    required this.path,
    required this.name,
    required this.kind,
    required this.mimeType,
    required this.text,
    required this.imageFeatures,
    required this.modifiedAt,
  });

  final String id;
  final String path;
  final String name;
  final ContentKind kind;
  final String mimeType;
  final String text;

  /// Image-side perceptual/embedding features. Empty for non-image content.
  final List<double> imageFeatures;

  final DateTime modifiedAt;
}

class LocalContentParser {
  static const MethodChannel _nativeParsers = MethodChannel('local_parsers');

  Future<ParsedContent> parse(File file) async {
    final extension = p.extension(file.path).toLowerCase();
    final stat = await file.stat();
    final bytes = await file.readAsBytes();
    final id = sha256.convert(bytes).toString();
    final name = p.basename(file.path);

    if (_isPlainText(extension)) {
      return ParsedContent(
        id: id,
        path: file.path,
        name: name,
        kind: ContentKind.text,
        mimeType: _mimeType(extension),
        text: utf8.decode(bytes, allowMalformed: true),
        imageFeatures: const <double>[],
        modifiedAt: stat.modified,
      );
    }

    if (extension == '.docx') {
      return ParsedContent(
        id: id,
        path: file.path,
        name: name,
        kind: ContentKind.document,
        mimeType: _mimeType(extension),
        text: await _parseDocx(bytes),
        imageFeatures: const <double>[],
        modifiedAt: stat.modified,
      );
    }

    if (extension == '.pdf') {
      return ParsedContent(
        id: id,
        path: file.path,
        name: name,
        kind: ContentKind.document,
        mimeType: _mimeType(extension),
        text: await _parsePdfWithPdfium(file.path),
        imageFeatures: const <double>[],
        modifiedAt: stat.modified,
      );
    }

    if (_isImage(extension)) {
      // Image indexing now combines three signal sources:
      //   1. Vision OCR text (real on-device text recognition)
      //   2. Image filename
      //   3. Image embedding (CoreML MobileCLIP / Vision feature print)
      final ocr = await _parseImageTextWithVision(file.path);
      final features = await _parseImageFeatures(file.path);
      final parts = <String>[
        if (name.isNotEmpty) name,
        if (ocr.isNotEmpty) ocr,
      ];
      return ParsedContent(
        id: id,
        path: file.path,
        name: name,
        kind: ContentKind.image,
        mimeType: _mimeType(extension),
        text: parts.join('\n'),
        imageFeatures: features,
        modifiedAt: stat.modified,
      );
    }

    return ParsedContent(
      id: id,
      path: file.path,
      name: name,
      kind: ContentKind.document,
      mimeType: _mimeType(extension),
      text: await _parseWithTika(file.path),
      imageFeatures: const <double>[],
      modifiedAt: stat.modified,
    );
  }

  Future<String> _parsePdfWithPdfium(String path) async {
    try {
      final result = await _nativeParsers.invokeMethod<String>(
        'extractPdfTextWithPdfium',
        {'path': path},
      );
      return result ?? '';
    } on PlatformException {
      return '';
    }
  }

  Future<String> _parseWithTika(String path) async {
    try {
      final result = await _nativeParsers.invokeMethod<String>(
        'extractDocumentTextWithTika',
        {'path': path},
      );
      return result ?? '';
    } on PlatformException {
      return '';
    }
  }

  Future<String> _parseImageTextWithVision(String path) async {
    try {
      final result = await _nativeParsers.invokeMethod<String>(
        'extractImageTextWithVision',
        {'path': path},
      );
      return (result ?? '').trim();
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  Future<List<double>> _parseImageFeatures(String path) async {
    try {
      final result = await _nativeParsers.invokeListMethod<double>(
        'extractImageFeaturePrint',
        {'path': path},
      );
      if (result == null) return const <double>[];
      return result.map((value) => value.toDouble()).toList(growable: false);
    } on PlatformException {
      return const <double>[];
    } on MissingPluginException {
      return const <double>[];
    }
  }

  Future<String> _parseDocx(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final document = archive.findFile('word/document.xml');
    if (document == null) return '';
    final xml =
        utf8.decode(document.content as List<int>, allowMalformed: true);
    return xml
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isPlainText(String extension) {
    return {'.txt', '.md', '.csv', '.json', '.html', '.htm', '.xml'}
        .contains(extension);
  }

  bool _isImage(String extension) {
    return {'.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp'}
        .contains(extension);
  }

  String _mimeType(String extension) {
    return switch (extension) {
      '.txt' => 'text/plain',
      '.md' => 'text/markdown',
      '.csv' => 'text/csv',
      '.json' => 'application/json',
      '.html' || '.htm' => 'text/html',
      '.xml' => 'application/xml',
      '.pdf' => 'application/pdf',
      '.docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.bmp' => 'image/bmp',
      '.webp' => 'image/webp',
      _ => 'application/octet-stream',
    };
  }
}

/// Computes lightweight perceptual image features (color histogram + 64-bit
/// difference hash) in pure Dart so we always have an image-side signal
/// even when CoreML is not available. Used as a stable fallback for visual
/// similarity.
class DartImageFeatures {
  static const int colorBins = 24; // 4 per channel * 3 channels
  static const int hashBits = 64;

  static List<double> compute(Uint8List bytes) {
    final histogram = List<double>.filled(colorBins, 0);
    var hash = 0;
    for (var i = 0; i + 1 < bytes.length; i += 3) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      final rBin = (r * 4 ~/ 256).clamp(0, 3);
      final gBin = (g * 4 ~/ 256).clamp(0, 3);
      final bBin = (b * 4 ~/ 256).clamp(0, 3);
      histogram[rBin] += 1;
      histogram[4 + gBin] += 1;
      histogram[8 + bBin] += 1;
      // Cheap difference hash: compare each byte with the next one.
      if (i + 8 < bytes.length) {
        final bit = bytes[i] > bytes[i + 1] ? 1 : 0;
        hash = (hash << 1) | bit;
      }
    }
    final total = histogram.fold<double>(0, (a, b) => a + b);
    if (total > 0) {
      for (var i = 0; i < histogram.length; i++) {
        histogram[i] /= total;
      }
    }
    final hashList = <double>[];
    for (var i = 0; i < hashBits; i++) {
      hashList.add(((hash >> (hashBits - 1 - i)) & 1).toDouble());
    }
    return [...histogram, ...hashList];
  }
}
