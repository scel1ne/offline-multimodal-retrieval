# Product Requirements Document

Author: Celine Song
Document version: 1.0
Status: Signed-off

## Sign-off

| Role | Name | Signature | Date |
| --- | --- | --- | --- |
| Product Owner | Celine Song | _signed_ | 2026-06-27 |
| Engineering Lead | Celine Song | _signed_ | 2026-06-27 |
| Accessibility Lead | Celine Song | _signed_ | 2026-06-27 |

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

## Acceptance Criteria

- App runs offline.
- User can add files, search them, filter results, and persist the index.
- Keyboard-only users can complete the main workflow.
- High contrast and font scaling are available.
- Documentation covers architecture, API, operations, testing, accessibility, OSS, risk, performance, demonstration, and portfolio.

## Change Log

| Date | Author | Change |
| --- | --- | --- |
| 2026-06-27 | Celine Song | Initial draft, scope finalized, signed-off for Week 1 delivery |

## Out of Scope (Current Submission)

- Cloud sync and multi-device sync.
- Telemetry, analytics, or any outbound network call.
- GitHub publication of the codebase.
- Windows / Linux desktop builds (macOS path is the production target for this submission).
