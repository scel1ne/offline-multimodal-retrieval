# Offline Accessible Multimodal Local Content Retrieval

Author: Celine Song

This repository contains the engineering deliverables for the Offline Accessible
Multimodal Local Content Retrieval System — an offline-first, cross-platform
content retrieval app. Work is split into week-scoped milestones covering
requirements, architecture, and the parsing pipeline.

## Project Goals

- Deliver a privacy-respecting, fully offline retrieval experience across
  desktop (macOS) and web.
- Support multimodal ingestion (text, documents, images) with on-device
  embeddings.
- Meet WCAG 2.1 AA accessibility expectations and open-source compliance
  requirements end-to-end.
- Maintain a clean, modular architecture that can be extended with new content
  types and retrieval strategies.

## Milestones

### Week 1 — Foundations (complete)

- Review software engineering best practices, WCAG 2.1 AA expectations, and
  open-source compliance rules.
- Finalize functional and non-functional requirements for an offline-first,
  cross-platform retrieval app.
- Validate the development environment: Flutter SDK, TensorFlow Lite, Git,
  Chroma DB, document parsing tools, and open-source dependencies.
- Curate a small local validation fixture set and document external datasets.
- Complete the initial risk assessment and mitigation plan.

### Week 2 — Architecture & Parsing (complete)

- Finalize the six-layer system architecture (File I/O, Parsing, Embedding,
  Vector Storage, Retrieval, UI & Accessibility).
- Rewrite the technical design document with class and sequence diagrams and
  the parsing data contract.
- Document module-level APIs for the parser, embedding engine, vector store,
  retrieval service, UI, and the C++ parser bridge.
- Implement the functional file-parsing module (`LocalContentParser`) with
  platform-channel-backed extractors for TXT, PDF, DOCX, PNG, and JPG, plus a
  color-histogram + dHash fallback for image inputs.
- Ship a 10-case Dart unit test suite for the parser and a Google Test C++
  bridge for the native side.

## Deliverables

### Week 1

- Project Requirements Document: `docs/PRD.md`
- Environment setup validation report: `docs/environment_setup.md`
- Curated local dataset repository: `docs/dataset_repository.md` and `fixtures/`
- Project risk management plan: `docs/risk_management.md`

### Week 2

- System architecture document: `docs/architecture.md`
- Technical design document: `docs/technical_design.md`
- Module API documentation: `docs/api.md`
- Functional parsing module: `lib/src/retrieval/local_content_parser.dart`
  with native bridge under `native/`
- Testing report: `docs/testing_report.md`

## Supporting Documents

- Accessibility review: `docs/accessibility_report.md`
- Open-source compliance review: `docs/oss_compliance.md`
- Strict requirements audit: `docs/strict_requirements_audit.md`
- Maintenance guide: `docs/maintenance_guide.md`

## Repository Layout

- `lib/` — Flutter application source (Dart)
- `native/` — Native C++ parser bridge
- `test/` — Dart unit and widget tests
- `integration_test/` — End-to-end Flutter integration tests
- `assets/` — Bundled tokenizer and TFLite / CoreML models
- `fixtures/` — Local validation fixtures
- `scripts/` — Build, packaging, and CI helper scripts
- `docs/` — Project documentation
