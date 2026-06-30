import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_accessible_retrieval/src/models/indexed_item.dart';
import 'package:offline_accessible_retrieval/src/parsing/local_content_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nativeParsers = MethodChannel('local_parsers');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeParsers, null);
  });

  test('parses plain text files', () async {
    final file = File('${Directory.systemTemp.path}/retrieval_parser_test.txt');
    await file.writeAsString('offline accessible semantic retrieval');

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.kind, ContentKind.text);
    expect(parsed.text, contains('semantic'));
    expect(parsed.mimeType, 'text/plain');
  });

  test('parses image files as image content', () async {
    final file = File('${Directory.systemTemp.path}/retrieval_parser_test.jpg');
    await file.writeAsBytes([1, 2, 3]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeParsers, (call) async {
      if (call.method == 'extractImageTextWithVision') {
        return 'a cat sitting on a mat';
      }
      if (call.method == 'extractImageFeaturePrint') {
        return <double>[0.1, 0.2, 0.3, 0.4];
      }
      return null;
    });

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.kind, ContentKind.image);
    expect(parsed.text, contains('retrieval_parser_test.jpg'));
    expect(parsed.text, contains('a cat sitting on a mat'));
    expect(parsed.mimeType, 'image/jpeg');
    expect(parsed.imageFeatures, isNotEmpty);
  });

  test('keeps image indexing alive when Vision OCR fails', () async {
    final file = File('${Directory.systemTemp.path}/retrieval_ocr_failed.png');
    await file.writeAsBytes([0x89, 0x50, 0x4e, 0x47]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeParsers, (call) async {
      throw PlatformException(code: 'parse_failed', message: 'no vision');
    });

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.kind, ContentKind.image);
    expect(parsed.text, contains('retrieval_ocr_failed.png'));
  });

  test('Tika bridge fallback returns empty text when platform throws',
      () async {
    final file = File('${Directory.systemTemp.path}/retrieval_tika_failed.rtf');
    await file.writeAsString('{rtf}');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeParsers, (call) async {
      if (call.method == 'extractDocumentTextWithTika') {
        throw PlatformException(code: 'parse_failed', message: 'no java');
      }
      return null;
    });

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.kind, ContentKind.document);
    expect(parsed.text, isEmpty);
  });

  test('DartImageFeatures returns a 24-bin histogram and 64-bit hash', () {
    final bytes = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));
    final features = DartImageFeatures.compute(bytes);
    expect(features.length, DartImageFeatures.colorBins + DartImageFeatures.hashBits);
    // Histogram should sum to ~1.
    final histogramSum =
        features.take(DartImageFeatures.colorBins).fold<double>(0, (a, b) => a + b);
    expect(histogramSum, closeTo(1, 0.01));
    // Hash bits are 0 or 1.
    final hashBits = features.skip(DartImageFeatures.colorBins);
    expect(hashBits.every((bit) => bit == 0 || bit == 1), isTrue);
  });

  test('extracts text from docx document xml', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'word/document.xml',
          '<w:document><w:t>Hello</w:t><w:t>offline DOCX</w:t></w:document>',
        ),
      );
    final file =
        File('${Directory.systemTemp.path}/retrieval_parser_test.docx');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.kind, ContentKind.document);
    expect(parsed.mimeType, contains('wordprocessingml'));
    expect(parsed.text, 'Hello offline DOCX');
  });

  test('returns empty text when docx has no document xml', () async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('empty.txt', 'empty'));
    final file = File('${Directory.systemTemp.path}/retrieval_empty.docx');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.text, isEmpty);
  });

  test('uses native Pdfium bridge for PDF files', () async {
    final file = File('${Directory.systemTemp.path}/retrieval_parser_test.pdf');
    await file.writeAsBytes([0x25, 0x50, 0x44, 0x46]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeParsers, (call) async {
      expect(call.method, 'extractPdfTextWithPdfium');
      expect(call.arguments, {'path': file.path});
      return 'pdfium text';
    });

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.mimeType, 'application/pdf');
    expect(parsed.text, 'pdfium text');
  });

  test('keeps PDF indexing alive when native parser fails', () async {
    final file = File('${Directory.systemTemp.path}/retrieval_failed.pdf');
    await file.writeAsBytes([0x25, 0x50, 0x44, 0x46]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeParsers, (call) async {
      throw PlatformException(
        code: 'parse_failed',
        message: 'xcrun cannot be used within an App Sandbox.',
      );
    });

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.kind, ContentKind.document);
    expect(parsed.mimeType, 'application/pdf');
    expect(parsed.text, isEmpty);
  });

  test('uses native Tika bridge for unsupported document files', () async {
    final file = File('${Directory.systemTemp.path}/retrieval_parser_test.rtf');
    await file.writeAsString('{rtf}');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeParsers, (call) async {
      expect(call.method, 'extractDocumentTextWithTika');
      expect(call.arguments, {'path': file.path});
      return 'tika text';
    });

    final parsed = await LocalContentParser().parse(file);

    expect(parsed.kind, ContentKind.document);
    expect(parsed.mimeType, 'application/octet-stream');
    expect(parsed.text, 'tika text');
  });
}
