# Technical Design Document (TDD)

**Author:** Celine Song
**Document version:** 2.0
**Status:** Signed-off
**Last updated:** 2026-06-30
**Scope:** Week 2 deliverable 4 — full technical design with class diagrams, sequence diagrams, data contracts, and the parsing-module design that backs Week 2 deliverable 2.

---

## 1. Sign-off

| Role | Name | Date |
|---|---|---|
| Engineering Lead | Celine Song | 2026-06-30 |
| Product Owner | Celine Song | 2026-06-30 |

## 2. Change Log

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0 | 2026-06-27 | Celine Song | Initial TDD outline (Week 1 placeholder). |
| 2.0 | 2026-06-30 | Celine Song | Filled in module structure, parser internals, sequence diagrams, and the data contract for `ParsedContent`. |

## 3. Module Map

The system is the same six-layer architecture described in [architecture.md](architecture.md). The map below is the implementation-level view: which files live in which layer and what the public class is.

| Layer | Directory | Public Class | Public Methods |
|---|---|---|---|
| 1 File I/O | `lib/src/app/` | `RetrievalApp` | `build(BuildContext)` |
| 2 Parsing | `lib/src/parsing/local_content_parser.dart` | `LocalContentParser` | `parse(File)` |
| 2 Parsing | `lib/src/parsing/local_content_parser.dart` | `DartImageFeatures` | `compute(Uint8List)` |
| 3 Embedding | `lib/src/embedding/tflite_embedding_engine.dart` | `TfliteEmbeddingEngine` | `load()`, `embedText(String)`, `embedImage(List<double>)` |
| 4 Storage | `lib/src/storage/chroma_vector_store.dart` | `ChromaVectorStore` | `upsertItem(IndexedItem)`, `query(...)`, `exportJson()`, `importJson(String)` |
| 5 Retrieval | `lib/src/retrieval/retrieval_service.dart` | `RetrievalService` | `ingestDirectory(Directory)`, `searchByText(...)`, `searchByImage(...)`, `clear()`, `exportIndex(String)`, `importIndex(String)` |
| 6 UI & A11y | `lib/src/ui/home_screen.dart` | `HomeScreen` | (Flutter widget) |
| Platform | `native/local_parsers.h` | `ExtractPdfTextWithPdfium`, `ExtractDocumentTextWithTika` | C++ free functions |

## 4. Parsing Module Design (Week 2 deliverable 2)

The parsing module is the centrepiece of Week 2. It is the only module that owns a `MethodChannel` to the native side, and it owns the format-routing logic.

### 4.1 Class Diagram

```
                ┌────────────────────────┐
                │   ParsedContent (DTO)  │
                ├────────────────────────┤
                │ id: String             │
                │ path: String           │
                │ name: String           │
                │ kind: ContentKind      │
                │ mimeType: String       │
                │ text: String           │
                │ imageFeatures: List    │
                │ modifiedAt: DateTime   │
                └───────────▲────────────┘
                            │ produces
                            │
┌─────────────────────┐     │     ┌──────────────────────┐
│ LocalContentParser  │─────┴─────│ DartImageFeatures    │
├─────────────────────┤           ├──────────────────────┤
│ + parse(File)       │           │ + compute(Uint8List) │
│   : Future<Parsed…> │           │   : List<double>     │
├─────────────────────┤           ├──────────────────────┤
│ - _parsePdfium      │           │ colorBins = 24       │
│ - _parseTika        │           │ hashBits  = 64       │
│ - _parseVision      │           └──────────────────────┘
│ - _parseFeaturePrint│
│ - _parseDocx        │
│ - _isPlainText      │
│ - _isImage          │
│ - _mimeType         │
└──────────▲──────────┘
           │ uses
           │
           │ MethodChannel('local_parsers')
           ▼
┌──────────────────────────────────────────────┐
│   Platform (native/)                         │
│   - ExtractPdfTextWithPdfium(path) → String  │
│   - ExtractDocumentTextWithTika(path) → Str  │
│   - extractImageTextWithVision(path)         │
│   - extractImageFeaturePrint(path) → List    │
└──────────────────────────────────────────────┘
```

### 4.2 Format Routing Table

| Extension | Branch | Strategy | Native call? |
|---|---|---|---|
| `.txt` `.md` `.csv` `.json` `.html` `.htm` `.xml` | `_isPlainText` | `utf8.decode(bytes, allowMalformed: true)` | No |
| `.docx` | `extension == '.docx'` | In-memory ZIP → read `word/document.xml` → strip tags, collapse whitespace | No |
| `.pdf` | `extension == '.pdf'` | Native PDFium text extract | Yes (`extractPdfTextWithPdfium`) |
| `.png` `.jpg` `.jpeg` `.gif` `.bmp` `.webp` | `_isImage` | Filename + Vision OCR text + image embedding | Yes (`extractImageTextWithVision`, `extractImageFeaturePrint`) |
| anything else | default | Native Tika | Yes (`extractDocumentTextWithTika`) |

### 4.3 Sequence: Plain Text Ingest

```
caller         LocalContentParser        file            dart:io
  │                  │                     │                │
  │ parse(file)      │                     │                │
  │─────────────────>│                     │                │
  │                  │ stat()              │                │
  │                  │─────────────────────────────────────>│
  │                  │<─ FileStat ─────────────────────────│
  │                  │ readAsBytes()       │                │
  │                  │─────────────────────────────────────>│
  │                  │<─ List<int> ────────────────────────│
  │                  │ sha256.convert      │                │
  │                  │ p.basename          │                │
  │                  │ utf8.decode         │                │
  │                  │ ParsedContent(...)  │                │
  │<─ ParsedContent ─│                     │                │
  │                  │                     │                │
```

### 4.4 Sequence: Image Ingest (Happy Path)

```
caller      LocalContentParser    native (macOS)    DartImageFeatures
  │               │                     │                   │
  │ parse(file)   │                     │                   │
  │──────────────>│                     │                   │
  │               │ extractImageText…   │                   │
  │               │────────────────────>│                   │
  │               │<───── "a cat…" ────│                   │
  │               │ extractImageFeaturePrint               │
  │               │────────────────────>│                   │
  │               │<──── [0.1,…,0.4] ──│                   │
  │               │                     │                   │
  │               │ (if native throws, fall back to        │
  │               │  filename only — never crash)           │
  │               │                     │                   │
  │               │ (DartImageFeatures not called here;     │
  │               │  it is a separate helper for callers    │
  │               │  that need a portable histogram+dhash)  │
  │<── ParsedContent (kind=image) ─────│                   │
```

### 4.5 Sequence: Image Ingest (Vision Unavailable)

```
caller      LocalContentParser    native (macOS)
  │               │                     │
  │ parse(file)   │                     │
  │──────────────>│                     │
  │               │ extractImageText…   │
  │               │────────────────────>│
  │               │<─ MissingPluginExc ─│
  │               │ (catch)             │
  │               │ extractImageFeaturePrint
  │               │────────────────────>│
  │               │<─ MissingPluginExc ─│
  │               │ (catch)             │
  │               │                     │
  │               │ text = filename     │
  │               │ imageFeatures = []  │
  │<── ParsedContent (kind=image, text=filename) │
```

The key property: **the ingest pipeline never aborts because a native feature is missing**. This is what the parser test suite asserts (`keeps image indexing alive when Vision OCR fails`).

### 4.6 Native Bridge Inventory

| Channel method | C++ symbol | Status |
|---|---|---|
| `extractPdfTextWithPdfium` | `ExtractPdfTextWithPdfium(const std::string&)` | Implemented (header + .cc native test for missing file) |
| `extractDocumentTextWithTika` | `ExtractDocumentTextWithTika(const std::string&)` | Implemented (header + .cc native test for missing file) |
| `extractImageTextWithVision` | (no C++ symbol) | Not yet implemented; falls back to filename via `MissingPluginException` |
| `extractImageFeaturePrint` | (no C++ symbol) | Not yet implemented; falls back to `imageFeatures: []` |

The Dart parser already routes the missing methods and degrades gracefully, so the architecture does not block when the macOS Vision/feature-print bridge is later wired in.

## 5. Data Contracts

### 5.1 `ParsedContent`

```dart
class ParsedContent {
  final String id;             // sha256(bytes) hex
  final String path;           // absolute path
  final String name;           // basename
  final ContentKind kind;      // text | document | image
  final String mimeType;       // RFC 6838
  final String text;           // empty when no text could be extracted
  final List<double> imageFeatures;  // empty for non-image
  final DateTime modifiedAt;   // from file.stat().modified
}
```

### 5.2 `ContentKind`

```dart
enum ContentKind { text, document, image }
```

The enum has three values, exactly matching the three legs of the data model: plain text, formatted documents (PDF/DOCX/anything else), and images.

### 5.3 `DartImageFeatures.compute`

- Input: any `Uint8List`.
- Output: `List<double>` of length `colorBins + hashBits` (24 + 64 = 88).
- First 24 entries: 4-bin-per-channel color histogram for R, G, B, each entry in `[0, 1]`. They sum to 1 for non-empty input.
- Last 64 entries: a 64-bit difference hash, each entry `0.0` or `1.0`.

## 6. Test Coverage Target

Week 2 deliverable 2 requires ≥80% unit test coverage of the parsing module. `test/parser_test.dart` currently covers the following cases (10 tests):

1. Plain text file → `ContentKind.text`, `text/plain`.
2. JPG with successful Vision mock → `ContentKind.image`, OCR text + features non-empty.
3. PNG with Vision failure → `ContentKind.image`, no crash, filename still indexed.
4. RTF with Tika failure → `ContentKind.document`, empty text, no crash.
5. `DartImageFeatures.compute` → 88 elements, histogram sums to ~1, hash bits are 0/1.
6. DOCX with valid `word/document.xml` → text extracted, tags stripped, whitespace collapsed.
7. DOCX with no `word/document.xml` → empty text, no crash.
8. PDF with successful Pdfium mock → `application/pdf`, text from native.
9. PDF with native failure → `application/pdf`, empty text, no crash.
10. RTF with successful Tika mock → `application/octet-stream`, text from native.

Run with:

```bash
.tooling/flutter/bin/flutter test test/parser_test.dart --coverage --no-pub
```

## 7. Out of Scope for This TDD

- The full `pubspec.yaml` dependency lock. See `docs/environment_setup.md` for the validated toolchain.
- The CI matrix. The architecture is single-developer/macOS for the current milestone.
- A custom embedding for non-English text. The bundled MobileBERT is the chosen text encoder for the prototype.

## 8. Open Design Questions

1. **Native Vision bridge.** When the macOS CoreML implementation lands, the channel contract is fixed; only the C++ side changes. The Dart side is already prepared.
2. **Streaming parser.** The current design holds full file bytes for the SHA-256. For multi-GB corpora, a streaming hash and a chunked parser are both on the table.
3. **Unicode policy.** TXT decode uses `allowMalformed: true`. A stricter policy (replacement character + log) is a possible Week 4 improvement.
