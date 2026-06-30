# Strict Requirements Audit

**Author:** Celine Song
**Document version:** 2.0
**Status:** Signed-off
**Last updated:** 2026-06-30
**Scope:** Week 2 supporting document. Confirms which project brief requirements are wired into the source, which are verified on the developer's machine, and which are still required to reach a full production runtime.

---

## 1. Sign-off

| Role | Name | Date |
|---|---|---|
| Engineering Lead | Celine Song | 2026-06-30 |
| Product Owner | Celine Song | 2026-06-30 |

## 2. Change Log

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0 | 2026-06-27 | Celine Song | Initial audit (23 unit tests, 99.51% coverage). |
| 2.0 | 2026-06-30 | Celine Song | Re-audited. Test count is now 33 after the parser refactor and the TFLite embedding test. |

## 3. Requirements Already Wired Into Source

| Brief requirement | Where it lives | Status |
|---|---|---|
| Flutter application source | `lib/main.dart`, `lib/src/app/retrieval_app.dart` | Done |
| TensorFlow Lite integration | `lib/src/embedding/tflite_embedding_engine.dart` (uses `tflite_flutter`) | Done |
| BERT text encoder | MobileBERT TFLite in `assets/models/bert_text_encoder.tflite` (gitignored) | Downloaded; loaded lazily |
| MobileCLIP image encoder | Apple CoreML package in `assets/models/mobileclip_s0_image.mlpackage` (gitignored) | Downloaded for macOS |
| MobileCLIP TFLite export | `scripts/export_mobileclip_onnx.py` + `scripts/convert_mobileclip_onnx_to_tflite.py` | Source checkpoint exported; TFLite conversion blocked on a transpose mismatch (see open items) |
| Chroma DB integration | `lib/src/storage/chroma_vector_store.dart` (HTTP v1 API) | Done with in-memory fallback |
| PDFium bridge | `native/local_parsers.h` `ExtractPdfTextWithPdfium` + macOS channel handler in `macos/Runner/` | Done |
| Apache Tika bridge | `native/local_parsers.h` `ExtractDocumentTextWithTika` + `scripts/extract_pdfium.py` invokes `.tooling/tika-app.jar` through the local JRE | Done |
| Flutter Test unit suite | `test/` (8 files, 33 tests) | Passing |
| Flutter integration tests | `integration_test/` (2 files: full workflow, accessibility flow) | Static-analyzed clean |
| Google Test native parser test | `native/local_parsers_test.cc` | Specification present, build wired through CMake |
| Image features fallback | `DartImageFeatures.compute` (24-bin histogram + 64-bit dhash in pure Dart) | Done |
| Accessible UI | `lib/src/ui/home_screen.dart` (Material 3 + high-contrast + font scale + live region) | Done; asserted in `integration_test/accessibility_flow_test.dart` |
| Index export / import | `RetrievalService.exportIndex` / `importIndex` + `ChromaVectorStore.exportJson` / `importJson` | Done |
| Companion web build | `web/index.html`, `web/app.js`, `web/styles.css` | Done |

## 4. Verified On This Machine (2026-06-30)

| Item | How it is verified |
|---|---|
| Flutter 3.44.4 / Dart 3.12.2 | `.tooling/flutter/bin/flutter --version` |
| Flutter static analysis | `.tooling/flutter/bin/flutter analyze --no-pub` reports no issues |
| Flutter unit suite | `.tooling/flutter/bin/flutter test --no-pub` reports `+33: All tests passed!` |
| Line coverage | `.tooling/flutter/bin/flutter test --coverage --no-pub` then `coverage/lcov.info` |
| Chroma CLI | `~/Library/Python/3.9/bin/chroma` reachable |
| CMake | `~/Library/Python/3.9/bin/cmake` reachable |
| Apache Tika | `.tooling/tika-app.jar` and `.tooling/tika-server-standard.jar` downloaded |
| Tika extraction smoke | Local JRE extracts text from a sample document |
| PDFium | `pypdfium2` import succeeds |
| BERT text encoder | Downloaded to `assets/models/bert_text_encoder.tflite` |
| MobileCLIP source checkpoint | Downloaded to `.downloads/mobileclip-s0/mobileclip_s0.pt` |
| MobileCLIP CoreML package | Downloaded to `assets/models/mobileclip_s0_image.mlpackage` |
| MobileCLIP ONNX export | Exported to `.downloads/mobileclip-s0/mobileclip_image_encoder.onnx` |
| JRE | `.tooling/jdk-21.0.11+10-jre` |
| CocoaPods | Local wrapper at `.tooling/pod-wrapper/pod` for sandboxed builds |

## 5. Still Required Before Full Production Runtime

1. **MobileCLIP TFLite conversion.** The `mobileclip_image_encoder.onnx` export works; the ONNX-to-TensorFlow path in `scripts/convert_mobileclip_onnx_to_tflite.py` currently hits an NCHW/NHWC dimension mismatch in the MobileCLIP-S0 token mixer. A true `assets/models/mobileclip_image_encoder.tflite` is blocked on resolving the transpose. The macOS CoreML package already covers the demo path, so this is not a Week 2 blocker.
2. **Local Chroma DB process.** A running Chroma server at `http://127.0.0.1:8000` is required for the strict path. The in-memory fallback covers the friendly path.
3. **Cross-platform desktop.** The current native bridge targets macOS. Porting to Windows/Linux is a Week 5+ item.
4. **Google Test build wiring.** `native/local_parsers_test.cc` is a Google Test specification. The CMake preset to build and run it is documented in [environment_setup.md](environment_setup.md) but is not invoked by the daily `flutter test` command.
5. **Signed + notarized macOS build.** The local `dist/offline_accessible_retrieval.app` is unsigned. A DMG pipeline is out of scope for the current milestone.

## 6. Coverage Target

The target is at least **90%** line coverage for the parser, embedding, retrieval, storage, and model modules combined. The Week 2 deliverable is **at least 80%** for the parsing module alone. The current overall line coverage is **99.23%** (see [testing_report.md](testing_report.md) for the full breakdown).

## 7. Open Items Carried Forward

| Item | Owner | Target |
|---|---|---|
| Resolve MobileCLIP ONNX → TFLite transpose | Engineering | Week 4 |
| Native Vision/FeaturePrint bridge in C++ | Engineering | Week 4 |
| Notarized DMG pipeline | Operations | Week 6 |
| Linux + Windows native bridge | Engineering | Week 8 |
