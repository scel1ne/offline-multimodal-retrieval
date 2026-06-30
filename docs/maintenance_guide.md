# Maintenance Guide

**Author:** Celine Song
**Document version:** 1.0
**Status:** Signed-off
**Last updated:** 2026-06-30
**Scope:** how to keep the project buildable, testable, and runnable on a developer's macOS machine, week over week. This is a supporting document for Week 2 deliverable on operational readiness.

---

## 1. Sign-off

| Role | Name | Date |
|---|---|---|
| Engineering Lead | Celine Song | 2026-06-30 |
| Operations | Celine Song | 2026-06-30 |

## 2. Change Log

| Version | Date | Author | Notes |
|---|---|---|---|
| 1.0 | 2026-06-30 | Celine Song | Initial maintenance guide. |

## 3. Source Layout

| Directory | Purpose | Approx. LOC |
|---|---|---|
| `lib/` | Flutter application source (production) | 2,502 |
| `test/` | Flutter unit tests (8 files) | 821 |
| `integration_test/` | Flutter integration tests (2 files) | 315 |
| `native/` | C++ parser bridge (`local_parsers.h`, `local_parsers_test.cc`) | 30 |
| `scripts/` | Python + shell helpers for the strict build | 252 |
| `web/` | Companion browser build | 1,532 |
| `fixtures/` | Local fixture files for manual ingest | 8 |
| `docs/` | All project documentation | 861 |
| `assets/models/` | Downloaded model files (gitignored, see `docs/model_assets_required.md`) | n/a |
| `assets/tokenizer/` | Bundled WordPiece vocab | n/a |

## 4. Daily Workflow

```bash
# 1. Pull the latest
git pull origin main

# 2. Use the vendored toolchain (so the .pub-cache and HOME stay local)
export HOME="$PWD/.home"
export PUB_CACHE="$PWD/.pub-cache"

# 3. Resolve packages
.tooling/flutter/bin/flutter pub get

# 4. Run the unit suite with coverage
.tooling/flutter/bin/flutter test --coverage --no-pub

# 5. Run the parser suite in isolation when iterating
.tooling/flutter/bin/flutter test test/parser_test.dart --coverage --no-pub

# 6. Run the desktop app
.tooling/flutter/bin/flutter run -d macos
```

The vendored `.tooling/flutter/` and local `.pub-cache/` mean the project does not depend on a global Flutter install. Re-cloning onto a new machine only needs the scripts in [environment_setup.md](environment_setup.md) to bootstrap.

## 5. Strict Build vs. Friendly Build

The repository supports two build modes.

| Mode | Trigger | Behaviour |
|---|---|---|
| Strict | `scripts/bootstrap_strict_env.sh` + `flutter run -d macos` with `HOME` and `PUB_CACHE` redirected | Real TFLite models, native PDFium, live Chroma. Failing fast is the point. |
| Friendly | `flutter run -d macos` with the system `HOME` | Falls back to in-memory embeddings and the in-memory vector store. The UI demo still works. |

The CI path is strict; the demo path is friendly. See [environment_setup.md](environment_setup.md) for the full validation list.

## 6. Dependency Update Procedure

1. Edit `pubspec.yaml` only. Never hand-edit `pubspec.lock`.
2. `flutter pub get` and inspect the lock diff.
3. Run `flutter test` and `flutter analyze`. Both must be clean.
4. Run a manual `flutter run -d macos` smoke test, especially the search-by-text and search-by-image paths.
5. Commit `pubspec.yaml` and `pubspec.lock` together with a message that names the upgraded package.

## 7. Model Asset Update

Model files live in `assets/models/` and are gitignored. To refresh them:

1. Follow the procedure in [model_assets_required.md](model_assets_required.md). Do not fabricate weights.
2. Place the new file under `assets/models/` with the documented name.
3. Restart the app so `TfliteEmbeddingEngine.load()` picks up the new file.
4. Re-run the unit suite to confirm the test that asserts "missing model fails clearly" still passes when the model is present.

## 8. Native Bridge Update

When the C++ side of the parser bridge changes:

1. Edit `native/local_parsers.h` and the matching `.cc` implementation.
2. Update `native/local_parsers_test.cc` to cover the new path or failure mode.
3. Rebuild the macOS app and re-run `flutter test test/parser_test.dart` to confirm the Dart side still routes the channel methods correctly.
4. If a new channel method is added, document it in [api.md](api.md) and [technical_design.md](technical_design.md) in the same change.

## 9. Documentation Update

Every change to a public Dart class, a platform channel method, or a model file is expected to ship with a documentation change. The doc files that must move in lockstep with code are:

- [architecture.md](architecture.md) — when a new layer is added or a dependency direction changes.
- [technical_design.md](technical_design.md) — when a sequence, format-routing rule, or data contract changes.
- [api.md](api.md) — when a public method or field is added, removed, or renamed.
- [risk_management.md](risk_management.md) — when a new technical risk appears or an existing one retires.
- [environment_setup.md](environment_setup.md) — when a toolchain version or a verification step changes.

## 10. Known Maintenance Gaps

- A signed + notarized DMG pipeline is not in place. The current `dist/offline_accessible_retrieval.app` is an unsigned local build.
- There is no scheduled dependency-update job. Dependencies move forward when the developer bumps them by hand.
- There is no multi-developer branch policy. The current workflow is a single `main` branch plus topic branches.
