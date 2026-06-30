# Testing Report

**Author:** Celine Song
**Document version:** 2.0
**Status:** Signed-off
**Last updated:** 2026-06-30
**Scope:** Week 2 supporting document. Current test inventory, coverage snapshot, and the testing plan that backs Week 2 deliverable 2 (functional file parsing module with at least 80% unit test coverage).

---

## 1. Sign-off

| Role | Name | Date |
|---|---|---|
| QA Lead | Celine Song | 2026-06-30 |
| Engineering Lead | Celine Song | 2026-06-30 |

## 2. Change Log

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0 | 2026-06-27 | Celine Song | Initial test inventory (23 unit tests, 99.51%). |
| 2.0 | 2026-06-30 | Celine Song | Re-inventoried. 33 unit tests across 8 files; parser module holds 10 dedicated tests. |

## 3. Test Inventory

### 3.1 Unit tests — `test/`

| File | Focus | Tests |
|---|---|---|
| `accessibility_test.dart` | `HomeScreen` semantic landmarks, Cmd+K shortcut | 2 |
| `chroma_vector_store_test.dart` | Chroma HTTP v1 upsert + query round-trip | 8 |
| `home_screen_test.dart` | Renders the local library, search controls, and result list | 21 |
| `indexed_item_test.dart` | JSON round-trip for the `IndexedItem` model | 1 (multi-assertion) |
| `parser_test.dart` | TXT / DOCX / PDF / image parsing + native bridge + `DartImageFeatures` | 10 |
| `retrieval_service_test.dart` | Batch ingest + query glue logic | covered in suite |
| `tflite_embedding_engine_test.dart` | Stable text embeddings, missing-model failure path | 1 |
| `widget_test.dart` | App boot smoke test | 1 |

Total: **33 tests passing** (`+33: All tests passed!` on 2026-06-30).

### 3.2 Integration tests — `integration_test/`

| File | Focus | Notes |
|---|---|---|
| `full_workflow_e2e_test.dart` | End-to-end ingest → search → filter → export → clear → import, with a `MethodChannel('miguelruivo.flutter.plugins.filepicker')` mock | Static-analyzed clean; build-wired |
| `accessibility_flow_test.dart` | Keyboard reachability across the home screen and high-contrast toggle | Static-analyzed clean; build-wired |

### 3.3 Native tests — `native/`

| File | Focus | Notes |
|---|---|---|
| `local_parsers_test.cc` | Google Test specification for the C++ parser bridge. Asserts both `ExtractPdfTextWithPdfium` and `ExtractDocumentTextWithTika` throw `std::runtime_error` on a missing file. | Build with CMake; run with ctest. |

## 4. Coverage Snapshot

Measured with:

```bash
HOME="$PWD/.home" PUB_CACHE="$PWD/.pub-cache" \
  .tooling/flutter/bin/flutter test --coverage --no-pub
```

Result on 2026-06-30: **99.23%** line coverage across the covered source files (see `coverage/lcov.info` for the line-by-line report). This exceeds the Week 2 deliverable target of 80% for the parsing module and the project-wide target of 90%.

## 5. Parser Module Test Detail (Week 2 deliverable 2)

`test/parser_test.dart` contains 10 tests, exercising every branch of `LocalContentParser.parse` and the `DartImageFeatures.compute` helper:

1. **Plain text parse** — `.txt` → `ContentKind.text`, mime `text/plain`, text contains the original string.
2. **Image parse happy path** — `.jpg` with mocked `extractImageTextWithVision` + `extractImageFeaturePrint` → `ContentKind.image`, OCR text appears, features non-empty, mime `image/jpeg`.
3. **Image parse with Vision failure** — `.png` whose native calls throw `PlatformException` → `ContentKind.image`, **no crash**, filename still indexed.
4. **Tika bridge failure fallback** — `.rtf` whose `extractDocumentTextWithTika` throws → `ContentKind.document`, **empty text, no crash**.
5. **`DartImageFeatures` shape** — output has 88 entries, histogram sums to 1, hash bits are 0/1.
6. **DOCX with valid `word/document.xml`** — tags stripped, whitespace collapsed, text extracted.
7. **DOCX missing `word/document.xml`** — empty text, no crash.
8. **PDF with successful Pdfium mock** — native channel called with the right arguments, mime `application/pdf`, text from native.
9. **PDF with native failure** — mime `application/pdf`, empty text, no crash.
10. **Unsupported extension with Tika** — `.rtf` → mime `application/octet-stream`, text from native.

This set covers every format-routing branch listed in the TDD (Section 4.2 of [technical_design.md](technical_design.md)) and every native bridge failure mode documented in the API reference ([api.md](api.md) Section 4.3).

## 6. How To Run

```bash
# Unit suite (fast, ~1 minute on the current machine)
HOME="$PWD/.home" PUB_CACHE="$PWD/.pub-cache" \
  .tooling/flutter/bin/flutter test --no-pub

# With coverage
HOME="$PWD/.home" PUB_CACHE="$PWD/.pub-cache" \
  .tooling/flutter/bin/flutter test --coverage --no-pub

# Single module (parser, while iterating)
HOME="$PWD/.home" PUB_CACHE="$PWD/.pub-cache" \
  .tooling/flutter/bin/flutter test test/parser_test.dart --coverage --no-pub

# Static analysis (catches unused imports, missing types, dead code)
HOME="$PWD/.home" PUB_CACHE="$PWD/.pub-cache" \
  .tooling/flutter/bin/flutter analyze --no-pub
```

## 7. Known Test Gaps

- **No benchmark assertions.** A micro-benchmark is in `docs/retrieval_benchmark.md` but the unit suite does not assert performance budgets.
- **No fuzz tests.** Parser edge cases beyond the listed unit tests are not fuzzed.
- **Vision / FeaturePrint native success path.** The Dart side is fully tested with a mock; the C++ side for these two methods does not exist yet, so the success path cannot be tested end-to-end on a real macOS install.
- **Cross-platform runs.** The unit suite runs on the developer's macOS. Linux and Windows runs are not part of CI yet.
