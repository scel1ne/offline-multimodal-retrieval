# System Architecture Design

**Author:** Celine Song
**Document version:** 1.0
**Status:** Signed-off
**Last updated:** 2026-06-30
**Scope:** Week 2 deliverable 1 — finalized system architecture for the Offline Accessible Multimodal Local Content Retrieval System.

---

## 1. Sign-off

| Role | Name | Date |
|---|---|---|
| Product Owner | Celine Song | 2026-06-30 |
| Engineering Lead | Celine Song | 2026-06-30 |
| Accessibility Lead | Celine Song | 2026-06-30 |

## 2. Change Log

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0 | 2026-06-30 | Celine Song | Initial six-layer architecture. Replaces the earlier outline. |

## 3. Architecture Goals

The system is an offline-first Flutter desktop application that lets a single user search and retrieve text, document, and image files from a local corpus. The architecture has to satisfy three non-negotiable goals:

1. **Offline-first** — every code path runs without a network. The vector store, embedding engine, and parser bridges are local processes or platform channels.
2. **Modular** — each cross-cutting concern (file I/O, parsing, embedding, storage, retrieval, UI) lives in its own module with a single public surface, so a swap in one layer (for example, replacing PDFium with another PDF library) does not ripple.
3. **Accessible by default** — accessibility is its own first-class layer, not a UI afterthought, so keyboard navigation, semantic landmarks, and high-contrast theming are not lost when a new screen is added.

## 4. Six-Layer Module Architecture

The application is divided into six layers. Layers only depend downward; no upward references are allowed.

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 6  UI & Accessibility Layer       lib/src/ui/                 │
│          (Home screen, search, filters, a11y landmarks, themes)     │
├─────────────────────────────────────────────────────────────────────┤
│ Layer 5  Retrieval Logic Layer          lib/src/retrieval/          │
│          (Retrieval service, scoring, filtering, export/import)    │
├─────────────────────────────────────────────────────────────────────┤
│ Layer 4  Vector Storage Layer           lib/src/storage/            │
│          (Chroma vector store client, index persistence)            │
├─────────────────────────────────────────────────────────────────────┤
│ Layer 3  Embedding Engine Layer         lib/src/embedding/          │
│          (TFLite BERT text + MobileCLIP image embedders)            │
├─────────────────────────────────────────────────────────────────────┤
│ Layer 2  Parsing Layer                  lib/src/parsing/            │
│          (Local content parser, native Pdfium/Tika bridges)         │
├─────────────────────────────────────────────────────────────────────┤
│ Layer 1  File I/O Layer                 lib/src/app/ + dart:io      │
│          (File pickers, recursive walk, batch ingestion)            │
├─────────────────────────────────────────────────────────────────────┤
│ Platform  Native                        native/ (C/C++ via channels)│
│          PDFium, Apache Tika, Apple Vision (planned)               │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.1 Layer 1 — File I/O Layer (`lib/src/app/`, `dart:io`)

**Responsibility:** locate and read files. Does not understand their content.

- Discovers files via `file_picker` (multi-select) and recursive directory walks through `dart:io`.
- Streams bytes to the Parsing Layer; never interprets content.
- Owns the SHA-256 content hash used as a stable item ID.
- Public surface: `FilePickerResult`-driven pick + `Iterable<File>` walk.

### 4.2 Layer 2 — Parsing Layer (`lib/src/parsing/local_content_parser.dart`)

**Responsibility:** turn raw bytes into structured `ParsedContent` with text and image features.

- Routes by extension: TXT/MD/CSV/JSON/HTML/XML → plain text decode; DOCX → in-memory ZIP + `word/document.xml` regex strip; PDF → native `ExtractPdfTextWithPdfium`; JPG/PNG/GIF/BMP/WebP → native Vision OCR + feature print with pure-Dart histogram + dhash fallback; everything else → native `ExtractDocumentTextWithTika`.
- Emits `ParsedContent` with `id`, `path`, `name`, `kind`, `mimeType`, `text`, `imageFeatures`, `modifiedAt`.
- All native calls degrade gracefully: a `PlatformException` or `MissingPluginException` returns empty text/empty features, never crashes the ingest.
- Public surface: `class LocalContentParser { Future<ParsedContent> parse(File file) }` and `class DartImageFeatures { static List<double> compute(Uint8List) }`.

### 4.3 Layer 3 — Embedding Engine Layer (`lib/src/embedding/tflite_embedding_engine.dart`)

**Responsibility:** map text and image features to fixed-size dense vectors.

- Text encoder: MobileBERT TFLite (`assets/models/bert_text_encoder.tflite`) plus the bundled WordPiece vocab (`assets/tokenizer/vocab.txt`).
- Image encoder: Apple MobileCLIP-S0 CoreML package (`assets/models/mobileclip_s0_image.mlpackage`) for macOS; pure-Dart histogram + 64-bit dhash (`DartImageFeatures`) as a portable fallback.
- Loading is deferred to the first embed call, not the app start, so unit tests do not require a real TFLite runtime.
- Public surface: `class TfliteEmbeddingEngine { Future<void> load(); Future<List<double>> embedText(String); Future<List<double>> embedImage(List<double> imageFeatures) }`.

### 4.4 Layer 4 — Vector Storage Layer (`lib/src/storage/chroma_vector_store.dart`)

**Responsibility:** persist and query the embedding index.

- Talks to a local Chroma DB HTTP server at `http://127.0.0.1:8000` over the v1 REST API (`/api/v1/collections`, `/api/v1/collections/{name}/add`, `/api/v1/collections/{name}/query`).
- Falls back to an in-memory cosine-similarity store when the server is unreachable, so the UI demo does not require a running Chroma instance.
- Public surface: `class ChromaVectorStore { Future<void> upsertItem(IndexedItem); Future<List<SearchResult>> query({required List<double> embedding, int topK}); Future<String> exportJson(); Future<void> importJson(String json) }`.

### 4.5 Layer 5 — Retrieval Logic Layer (`lib/src/retrieval/retrieval_service.dart`)

**Responsibility:** compose the lower layers to answer a search and to manage the local index.

- Glues `LocalContentParser` + `TfliteEmbeddingEngine` + `ChromaVectorStore` together.
- Exposes the batch ingestion API (ingest a directory → for every file: parse, embed, upsert).
- Exposes the single-query API (text/image → embed → vector query → merge with text highlights → `SearchResult` list with per-document occurrence pager).
- Public surface: `class RetrievalService { Future<void> ingestDirectory(Directory); Future<List<SearchResult>> searchByText(String query, {int topK}); Future<List<SearchResult>> searchByImage(String imagePath, {int topK}); Future<void> clear(); Future<void> exportIndex(String path); Future<void> importIndex(String path) }`.

### 4.6 Layer 6 — UI & Accessibility Layer (`lib/src/ui/home_screen.dart`)

**Responsibility:** render the app, expose every interaction to keyboard and assistive tech.

- Material 3 light/dark theme with gradients, animated panels, and progress indicators.
- Search bar, result list with per-document occurrence pager (prev/next), filter chips, import/export buttons.
- **Accessibility is not optional**: every interactive widget has a `Semantics` label; the search status updates a `liveRegion`; a high-contrast toggle and a font-scale slider live in the app bar; `Tooltip` messages describe icon-only buttons; full keyboard reachability is asserted by `integration_test/accessibility_flow_test.dart`.
- Public surface: `class HomeScreen extends StatefulWidget` and the supporting `Theme`/`Semantics` helpers.

## 5. Cross-Cutting Concerns

- **Configuration.** All tunables (Chroma URL, model paths, parser-extension list) live as `const` at the top of each layer's main class. There is no global mutable config.
- **Errors.** Each layer returns the richest information it can; failures propagate upward as typed results, never raw `Exception`s. The Parsing Layer in particular swallows native `PlatformException` and substitutes empty text so the ingest pipeline survives a single bad file.
- **Logging.** Each layer emits structured `print` output with a `[layer]` prefix. This is the minimum log surface a desktop user needs without a real logger dependency.
- **Accessibility.** The Accessibility concern is layered as cross-cutting rather than bolted onto UI: every widget that is user-reachable has a `Tooltip`, every state change announces itself through a `Semantics(liveRegion: true)`, and focus styles are defined once in the theme and inherited by every interactive element.

## 6. Dependency Direction Rules

1. UI may call Retrieval; UI must not call Storage, Embedding, Parsing, or I/O directly.
2. Retrieval may call Embedding, Storage, and Parsing.
3. Embedding and Storage are siblings: they must not import each other.
4. Parsing depends on I/O (to read the file) but not on Embedding or Storage.
5. The Platform (`native/`) is reachable only through Parsing's `MethodChannel('local_parsers')`. No other layer talks to native.

A change in any one layer that requires changing a layer above it is treated as an architecture smell and is reverted.

## 7. Out of Scope for This Revision

- A packaging story (DMG, notarization) — handled separately in `docs/maintenance_guide.md`.
- A sync story across machines — the architecture is strictly local; multi-device sync is deferred to a future milestone.
- Replacing the Chroma HTTP client with an embedded native store — the in-memory fallback already covers the demo path; the swap is a future optimization.

## 8. Open Architectural Questions

1. **Image feature parity.** MobileCLIP-S0 is macOS-only (CoreML). The Dart histogram + dhash fallback is portable but lower-fidelity. A unified embedder for Windows/Linux is a Week 5+ question.
2. **Streaming ingest.** Batch ingestion currently holds the full file in memory to compute the SHA-256. A streaming hash is desirable once corpus size exceeds available RAM.
