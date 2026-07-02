# Product Requirements Document

Author: Celine Song
Document version: 1.1
Status: Signed-off
Last updated: 2026-07-02

## Sign-off

| Role | Name | Signature | Date |
| --- | --- | --- | --- |
| Product Owner | Celine Song | _signed_ | 2026-06-27 |
| Engineering Lead | Celine Song | _signed_ | 2026-07-02 |
| Accessibility Lead | Celine Song | _signed_ | 2026-07-02 |

> Version 1.1 adds a Tech Stack section, formal Interface Definitions, and a
> basic UX Flow. The functional and non-functional requirements in
> §§ "Goals", "Non-Goals", and "Acceptance Criteria" are unchanged.

## Problem

Users need to search local unstructured content such as notes, PDFs, documents, screenshots, and images without uploading private data to cloud services. The product must be usable by keyboard and screen-reader users.

## Goals

- Offline-first local content retrieval.
- Multimodal support for text files, documents, and images.
- Accessible interface aligned with WCAG 2.1 AA.
- Cross-platform production path.
- Open-source compliant, documented, and testable codebase.

## Non-Goals

- Cloud synchronization.
- Telemetry.
- GitHub publication in the current local delivery.

## Submitted Application Scope

- Local file ingestion.
- Metadata extraction.
- Text tokenization and vectorization.
- Image color and perceptual feature extraction.
- Hybrid ranking.
- Local index persistence.
- Export/import.
- Accessible Flutter desktop UI.

## Production Scope

- Flutter desktop app.
- TensorFlow Lite BERT text embeddings.
- MobileCLIP image embeddings.
- PDFium and Apache Tika parsing.
- Local Chroma DB vector storage.
- Google Test and Flutter Test automation.

## Tech Stack

| Layer | Technology | Role |
| --- | --- | --- |
| Application framework | Flutter (Dart 3.4+) | Cross-platform UI, widget composition, accessibility primitives |
| UI language | Dart | Flutter widget code, service classes, tests |
| State / theming | Material 3 (`ColorScheme`, `ThemeData`) | Light, dark, and high-contrast themes |
| Text embedding | TensorFlow Lite — MobileBERT | `assets/models/bert_text_encoder.tflite` + WordPiece vocab |
| Image embedding (macOS) | Apple CoreML — MobileCLIP-S0 | `assets/models/mobileclip_s0_image.mlpackage` |
| Image embedding (portable fallback) | Pure-Dart histogram + 64-bit dHash | `DartImageFeatures.compute(Uint8List)` |
| PDF parsing | PDFium (via `pypdfium2` / C++ binding) | `ExtractPdfTextWithPdfium(path)` in `native/` |
| Document parsing | Apache Tika (local JRE) | `ExtractDocumentTextWithTika(path)` in `native/` |
| Image OCR (planned) | Apple Vision | `extractImageTextWithVision` channel |
| Vector store | Chroma DB v1 REST (local server) | `ChromaVectorStore` in `lib/src/storage/` |
| Local ranking fallback | TF-IDF + multimodal cosine | `HomeScreen._score` hybrid ranker |
| Native bridge | Flutter `MethodChannel('local_parsers')` | Dart ↔ C++ call boundary |
| Native build | CMake + Google Test | `native/local_parsers_test.cc` |
| File picking | `file_picker` (multi-select) | `_pickAndIndex` ingestion path |
| Persistence | JSON file in user-selected path | `Export` / `Import` index |
| Testing | `flutter_test`, `integration_test`, Google Test | Unit, widget, integration, and C++ layers |
| Linting | `flutter_lints` 4.x | `analysis_options.yaml` |

All model files, Tika JAR, PDFium bindings, and Chroma DB are local — no
network calls are made at runtime.

## Interface Definitions

The system is divided into six layers (see `docs/architecture.md`). The
interfaces below are the only contracts a layer is allowed to expose upward.
Every signature is `async`; failures are surfaced as empty results rather than
exceptions so that a single bad file does not abort a batch.

### Parsing — `lib/src/parsing/local_content_parser.dart`

```dart
enum ContentKind { text, document, image }

class ParsedContent {
  final String id;            // SHA-256 hex of raw bytes
  final String path;          // absolute path
  final String name;          // basename
  final ContentKind kind;
  final String mimeType;      // RFC 6838
  final String text;          // extracted text, '' on failure
  final List<double> imageFeatures;  // 88-dim for images
  final DateTime modifiedAt;
}

class LocalContentParser {
  Future<ParsedContent> parse(File file);
}

class DartImageFeatures {
  static const int colorBins = 24;   // 4 bins × 3 channels
  static const int hashBits  = 64;
  static List<double> compute(Uint8List bytes);
}
```

Routes by extension: TXT/MD/CSV/JSON/HTML/XML → plain-text decode; DOCX →
in-memory ZIP regex strip; PDF → native `ExtractPdfTextWithPdfium`;
JPG/PNG/GIF/BMP/WebP → native Vision OCR + feature print with pure-Dart
fallback; anything else → native `ExtractDocumentTextWithTika`.

### Embedding — `lib/src/embedding/tflite_embedding_engine.dart`

```dart
class TfliteEmbeddingEngine {
  Future<void> load();
  Future<List<double>> embed(ParsedContent parsed);  // multimodal
  Future<List<double>> embedQuery(String text);      // text-only query
}
```

`load()` is deferred to the first embed call. The image-side half of the
embedding is `DartImageFeatures.compute` unless the macOS CoreML package is
available.

### Storage — `lib/src/storage/chroma_vector_store.dart`

```dart
class IndexedItem { /* id, path, name, kind, mimeType, text, imageFeatures, embedding, modifiedAt */ }
class SearchResult { final IndexedItem item; final double score; final List<MatchOccurrence> occurrences; }

class ChromaVectorStore {
  Future<void> upsert(IndexedItem item);
  Future<List<SearchResult>> query(List<double> embedding, {int topK = 10});
  Future<String> exportJson();
  Future<void> importJson(String json);
}
```

Falls back to an in-memory cosine-similarity store when the Chroma HTTP server
at `http://127.0.0.1:8000` is unreachable, so the UI demo never blocks on a
missing service.

### Retrieval — `lib/src/retrieval/retrieval_service.dart`

```dart
class RetrievalService {
  RetrievalService({
    required LocalContentParser parser,
    required TfliteEmbeddingEngine embeddingEngine,
    required ChromaVectorStore vectorStore,
  });

  Future<List<double>> embedForIndexing(ParsedContent parsed);
  Future<List<double>> embedQuery(String text);
  Future<IndexedItem> ingest(File file);
  Future<List<SearchResult>> search(String query);
}
```

`ingest(file)` is the canonical "add one file" entry point and is composed
of `parser.parse → embeddingEngine.embed → vectorStore.upsert`.
`search(query)` is the canonical "find me N items" entry point and is
composed of `embedQuery → vectorStore.query`.

### Native C++ — `native/local_parsers.h`

```cpp
std::string ExtractPdfTextWithPdfium(const std::string& path);
std::string ExtractDocumentTextWithTika(const std::string& path);
```

Both throw `std::runtime_error` on missing or unreadable input. They are
reached only through `MethodChannel('local_parsers')` from the parsing layer.

### UI — `lib/src/ui/home_screen.dart`

```dart
class HomeScreen extends StatefulWidget {
  const HomeScreen({required RetrievalService retrievalService, super.key});
}
```

The UI does not call storage, embedding, or parsing directly — it goes
through `RetrievalService` only.

## User Experience Flow

The product is a single-window Flutter desktop app. The flow below covers
the four tasks a user needs to complete: open the app, add files, search,
and manage the index.

### 1. Open the app

The user launches `offline_accessible_retrieval`. The window opens to the
**Home** screen with two panels:

- **Library** (left, fixed 400 px on wide layouts, stacked on narrow
  layouts): shows the count of indexed files, a drop-target, and the action
  buttons (`Choose files`, `Export`, `Import`, `Clear`).
- **Search** (right, fills remaining space): shows a search field, filter
  chips, sort selector, and a result list.

If the library is empty, the search panel shows
"Add files to start searching." Status text under the drop-target reads
"No files indexed yet." and is exposed as a `Semantics(liveRegion: true)`
region for screen readers.

### 2. Add files

The user has three ways to add files:

1. **Drop into the drop-target.** The drop-target accepts
   `txt, md, csv, json, html, htm, xml, pdf, docx, png, jpg, jpeg, gif, bmp,
   webp`. While indexing, a linear progress bar appears and the status text
   becomes "Indexing…" via the live region.
2. **Click "Choose files"** to open a multi-select file picker filtered to
   the same extension list.
3. **Click "Import"** to load a previously exported index JSON. The status
   text becomes "N records imported."

After indexing, the library list updates in place: each entry shows the
file name, kind (`text` / `document` / `image`), formatted size, and a
token count. The status line reads "N files indexed. Library has M files."

### 3. Search

The user types into the search field. The shortcut **⌘K / Ctrl-K** focuses
the field from anywhere in the window (WCAG 2.1.1 Keyboard).

While the user types, the result list re-ranks live:

- A type-filter chip is set to **All** by default; tapping **Text**,
  **Documents**, or **Images** narrows the list.
- The sort selector offers **Relevance** (default, hybrid score in
  `[0, 1]`), **Name** (ascending basename), and **Newest** (descending
  modification time).
- Each result card shows the file name, a match count, and a
  "N% match" pill. Tapping the card expands an **Occurrence Pager** that
  walks through every match inside the document with a snippet, a position
  bar, and Prev/Next buttons.

If the query yields no hits, the panel shows a centered "No matching
results" empty state. The status line ("N results for "query"") is
announced through the same live region.

### 4. Manage the index

The user can:

- **Export** the index to a JSON file (`offline-retrieval-index.json`) via
  a Save dialog. Use case: move the index between machines.
- **Import** a previously exported JSON to restore the library without
  re-parsing the original files.
- **Clear** the in-memory index. The status line becomes "Index cleared."

### 5. Accessibility controls (always available)

The app bar exposes three controls on every screen:

- **Light / Dark mode** toggle.
- **Standard / High contrast** toggle (uses `ColorScheme.highContrastLight`
  and a 1.5-px outline on every card).
- **Text scale** slider from 0.9× to 1.4× in 5 stops. The current value is
  announced as "Text N.Nx" through the slider's `Semantics` label.

Every interactive widget has a `Tooltip` and a `Semantics` label; keyboard
reachability is asserted by `integration_test/accessibility_flow_test.dart`.

### 6. Error handling

The user is never shown a raw exception. Failure paths:

- A native bridge that throws (`PlatformException`,
  `MissingPluginException`) returns empty text and the file is still added
  with a metadata-only record.
- The Chroma HTTP server being down triggers the in-memory fallback, so
  searches keep working.
- An embedding failure is swallowed and the local TF-IDF ranker takes
  over, so the result list is never empty when the library is not.

Each of these states is communicated through the live-region status text
under the drop-target.

## Acceptance Criteria

- App runs offline.
- User can add files, search them, filter results, and persist the index.
- Keyboard-only users can complete the main workflow.
- High contrast and font scaling are available.
- Documentation covers architecture, API, operations, testing, accessibility, OSS, risk, performance, demonstration, and portfolio.
- The PRD specifies the tech stack, the layer-to-layer interface contracts,
  and the basic UX flow described above.

## Change Log

| Date | Author | Change |
| --- | --- | --- |
| 2026-06-27 | Celine Song | Initial draft, scope finalized, signed-off for Week 1 delivery |
| 2026-07-02 | Celine Song | v1.1 — added Tech Stack, Interface Definitions, and UX Flow sections per engineering lead feedback |

## Out of Scope (Current Submission)

- Cloud sync and multi-device sync.
- Telemetry, analytics, or any outbound network call.
- GitHub publication of the codebase.
- Windows / Linux desktop builds (macOS path is the production target for this submission).
