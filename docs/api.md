# Module API Reference

**Author:** Celine Song
**Document version:** 2.0
**Status:** Signed-off
**Last updated:** 2026-06-30
**Scope:** Week 2 deliverable 3 — reference for every public Dart symbol in the application, plus the native C++ surface used by the parsing layer.

---

## 1. Sign-off

| Role | Name | Date |
|---|---|---|
| Engineering Lead | Celine Song | 2026-06-30 |
| Accessibility Lead | Celine Song | 2026-06-30 |

## 2. Change Log

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0 | 2026-06-27 | Celine Song | Placeholder outline. |
| 2.0 | 2026-06-30 | Celine Song | Filled in all public Dart classes and the native C++ surface. |

## 3. Conventions

- All public Dart symbols are exported from their layer's main file. No barrel `library` is used; callers import the source file directly so the dependency direction is visible at the call site.
- All public Dart methods are `async` and return a `Future<T>`. There are no synchronous I/O calls in the public surface.
- Errors from native bridges surface as empty results (`''` or `const <double>[]`), not exceptions, so a single failing file does not abort a batch. Logic errors (bad arguments) still throw.

## 4. Parsing Layer — `lib/src/parsing/local_content_parser.dart`

### 4.1 `class ParsedContent`

DTO produced by `LocalContentParser.parse`.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | SHA-256 hex of the raw bytes. Stable across re-ingest. |
| `path` | `String` | Absolute path of the source file. |
| `name` | `String` | Basename of the source file. |
| `kind` | `ContentKind` | One of `text`, `document`, `image`. |
| `mimeType` | `String` | RFC 6838 MIME type, e.g. `application/pdf`, `image/jpeg`. |
| `text` | `String` | Concatenated extracted text. Empty if extraction failed. |
| `imageFeatures` | `List<double>` | Image-side embedding / histogram. Empty for non-image. |
| `modifiedAt` | `DateTime` | File modification time, from `File.stat().modified`. |

Constructor:

```dart
const ParsedContent({
  required String id,
  required String path,
  required String name,
  required ContentKind kind,
  required String mimeType,
  required String text,
  required List<double> imageFeatures,
  required DateTime modifiedAt,
});
```

### 4.2 `enum ContentKind`

```dart
enum ContentKind { text, document, image }
```

### 4.3 `class LocalContentParser`

Public method:

```dart
Future<ParsedContent> parse(File file);
```

Behaviour:
- Reads the file's `stat` and bytes, computes the SHA-256 ID, and dispatches by extension.
- Plain text: `utf8.decode(bytes, allowMalformed: true)`.
- DOCX: in-memory ZIP, `word/document.xml` regex strip + whitespace collapse.
- PDF: native `extractPdfTextWithPdfium` (falls back to empty on `PlatformException`).
- Image: native `extractImageTextWithVision` + `extractImageFeaturePrint` (falls back to filename-only text and empty features on `PlatformException` / `MissingPluginException`).
- Anything else: native `extractDocumentTextWithTika` (falls back to empty on `PlatformException`).

### 4.4 `class DartImageFeatures`

```dart
static const int colorBins = 24;  // 4 bins per channel * 3 channels
static const int hashBits  = 64;

static List<double> compute(Uint8List bytes);
```

Output layout:
- `[0..24)` — R, G, B histograms (4 bins each), normalised to sum to 1.
- `[24..88)` — 64-bit difference hash, each entry `0.0` or `1.0`.

## 5. Embedding Layer — `lib/src/embedding/tflite_embedding_engine.dart`

### 5.1 `class TfliteEmbeddingEngine`

```dart
Future<void> load();
Future<List<double>> embedText(String text);
Future<List<double>> embedImage(List<double> imageFeatures);
```

Behaviour:
- `load()` is deferred to the first embed call, not the app start.
- Text encoder is MobileBERT TFLite at `assets/models/bert_text_encoder.tflite`; tokens come from `assets/tokenizer/vocab.txt`.
- Image encoder is the Apple MobileCLIP-S0 CoreML package on macOS; on other platforms the call returns a Dart histogram + dhash derived from `imageFeatures`.
- A real model file is required. The test suite asserts that loading throws clearly when the model is missing rather than silently fabricating embeddings.

## 6. Storage Layer — `lib/src/storage/chroma_vector_store.dart`

### 6.1 `class ChromaVectorStore`

```dart
Future<void> upsertItem(IndexedItem item);
Future<List<SearchResult>> query({
  required List<double> embedding,
  int topK = 10,
});
Future<String> exportJson();
Future<void> importJson(String json);
```

Behaviour:
- Talks to `http://127.0.0.1:8000` over the Chroma v1 REST API.
- Falls back to an in-memory cosine-similarity store when the server is unreachable, so the UI is usable without a running Chroma process.
- `exportJson` / `importJson` round-trip the whole index, so a user can move a corpus between machines.

## 7. Retrieval Layer — `lib/src/retrieval/retrieval_service.dart`

### 7.1 `class RetrievalService`

```dart
Future<void> ingestDirectory(Directory dir);
Future<List<SearchResult>> searchByText(String query, {int topK = 10});
Future<List<SearchResult>> searchByImage(String imagePath, {int topK = 10});
Future<void> clear();
Future<void> exportIndex(String path);
Future<void> importIndex(String path);
```

Behaviour:
- `ingestDirectory` walks the directory, parses each file via `LocalContentParser`, embeds via `TfliteEmbeddingEngine`, and upserts via `ChromaVectorStore`.
- `searchByText` embeds the query with the text encoder, queries the vector store, and merges results with text highlight occurrences for the per-document pager.
- `searchByImage` is the same pipeline with the image encoder.
- `exportIndex` / `importIndex` delegate to the storage layer and write to a user-selected file.

## 8. Models — `lib/src/models/`

### 8.1 `class IndexedItem` — `lib/src/models/indexed_item.dart`

The persisted record for one indexed file.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | SHA-256 hex of the raw bytes. |
| `path` | `String` | Absolute path. |
| `name` | `String` | Basename. |
| `kind` | `ContentKind` | `text` / `document` / `image`. |
| `mimeType` | `String` | RFC 6838. |
| `text` | `String` | Extracted text. |
| `imageFeatures` | `List<double>` | For image kind. |
| `embedding` | `List<double>` | Cached embedding, populated by the retrieval layer. |
| `modifiedAt` | `DateTime` | File modification time. |

### 8.2 `class SearchResult` — `lib/src/models/search_result.dart`

One hit in a query result list.

| Field | Type | Description |
|---|---|---|
| `item` | `IndexedItem` | The matched indexed item. |
| `score` | `double` | Cosine similarity in `[-1, 1]`. |
| `occurrences` | `List<MatchOccurrence>` | Per-match text spans for the pager. |

## 9. UI & Accessibility — `lib/src/ui/home_screen.dart`

### 9.1 `class HomeScreen extends StatefulWidget`

Renders the full app: search bar, result list with prev/next pager, filter chips, import/export buttons, high-contrast toggle, font-scale slider.

Accessibility surface:
- Every interactive element has a `Tooltip` and a `Semantics` label.
- Status changes are announced through a `Semantics(liveRegion: true)` widget.
- Keyboard reachability is asserted by `integration_test/accessibility_flow_test.dart`.

## 10. Platform C++ — `native/local_parsers.h`

### 10.1 `std::string ExtractPdfTextWithPdfium(const std::string& path);`

Extracts plain text from a PDF using the bundled PDFium. Throws `std::runtime_error` if the file is missing or unreadable.

### 10.2 `std::string ExtractDocumentTextWithTika(const std::string& path);`

Extracts plain text from a non-PDF, non-DOCX, non-image document by invoking the local Apache Tika server. Throws `std::runtime_error` if Tika is unreachable or the file cannot be parsed.

### 10.3 Native test

`native/local_parsers_test.cc` is a Google Test file asserting both functions reject a missing file with `std::runtime_error`. Build with CMake, link Google Test, and run with `ctest`. See `docs/environment_setup.md` for the toolchain.

## 11. Out of Scope for This Reference

- Internal helper functions prefixed with `_` are documented in the source files only; this document is the public surface.
- The `lib/main.dart` and `lib/src/app/retrieval_app.dart` wiring is described in [architecture.md](architecture.md), not here.
- Platform-specific build flags (CocoaPods, Gradle, CMake presets) are in [environment_setup.md](environment_setup.md).
