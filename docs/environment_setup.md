# Environment Setup Validation Report

Author: Celine Song
Validated on: 2026-06-27
Machine: macOS, Apple Silicon

## Purpose

This report validates that the Week 1 development environment can support the
planned offline, accessible, multimodal retrieval application. It documents the
toolchain required for future implementation work without submitting the full
application source code in the Week 1 repository.

## Required Environment

| Component | Purpose | Week 1 Status |
| --- | --- | --- |
| Git | Source control and submission workflow | Configured |
| Flutter SDK | Cross-platform desktop application framework | Installed locally |
| Dart | Flutter application language/runtime | Available through Flutter |
| TensorFlow Lite | Local embedding model runtime target | Dependency path identified |
| Chroma DB | Local vector database target | CLI installed and verified |
| PDFium / pypdfium2 | PDF text extraction target | Python package verified |
| Apache Tika | Office/document text extraction target | JAR downloaded and verified |
| Java runtime | Runs Apache Tika tooling | Temurin JRE available |
| CMake | Native test/build support | Installed |
| WCAG 2.1 AA references | Accessibility acceptance baseline | Reviewed |
| OSS compliance checklist | License and dependency review | Drafted |

## Validation Evidence

The following checks were completed during Week 1:

- Flutter SDK and bundled Dart are available on the local machine.
- Chroma CLI can be invoked locally for future vector-store validation.
- CMake is available for native build/test work.
- `pypdfium2` imports successfully for PDF extraction experiments.
- Apache Tika app/server JARs are available for document parsing validation.
- A local Java runtime is available for Tika execution.
- BERT/MobileCLIP model asset requirements are documented for later weeks.
- The repository has a `.gitignore` policy to avoid committing large generated
  artifacts, model binaries, build outputs, local caches, and release bundles.

## Reproducibility Checklist

For a fresh machine, future implementation weeks should:

1. Install or download Flutter SDK.
2. Run `flutter doctor` and resolve required desktop build warnings.
3. Install Chroma DB CLI or prepare an equivalent local vector-store service.
4. Install Java and download Apache Tika.
5. Install `pypdfium2` or configure a PDFium binding.
6. Download model files only after license review.
7. Keep large datasets and generated build artifacts out of source control.

## Week 1 Sign-off

The required development environment has been reviewed and is sufficient for
starting the implementation phase.

| Role | Name | Signature | Date |
| --- | --- | --- | --- |
| Environment Owner | Celine Song | _signed_ | 2026-06-27 |
