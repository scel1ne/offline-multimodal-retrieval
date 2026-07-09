# Model Accuracy Validation Report

**Author:** Celine Song
**Document version:** 1.0
**Status:** Week 3 draft
**Last updated:** 2026-07-09

## 1. Scope

This report supports the Week 3 deliverable for a local multimodal embedding
engine. It records the validation plan, current runnable checks, and remaining
production-model validation work.

## 2. Validation Targets

| Area | Target | Current status |
|---|---|---|
| Text embedding | Stable local embedding for repeat text queries | Covered by `test/tflite_embedding_engine_test.dart` |
| Image embedding | Local image feature vector when image bytes are available | Covered by tensor conversion and fallback feature tests |
| Multimodal shape | Text and image vectors concatenate into one normalized vector | Covered by embedding query and content embedding tests |
| Offline behavior | No network dependency during embedding tests | Covered by local fallback path |
| Production accuracy | Validate real BERT and MobileCLIP outputs on NQ and COCO samples | Pending real model placement |

## 3. Dataset Plan

| Dataset | Validation use |
|---|---|
| Natural Questions | Text query-to-document semantic retrieval checks |
| COCO | Image embedding and text-to-image retrieval checks |

## 4. Current Results

The committed unit tests validate deterministic behavior, vector normalization,
tokenization, image tensor preparation, missing-model error reporting, and the
fallback embedding path. These checks confirm that the Week 3 engine is
functionally runnable in an offline development environment.

Real production accuracy metrics are not claimed in this draft because the
large model binaries are excluded from Git. Once the local model files listed
in `assets/models/README.md` are present, the validation run should record:

| Metric | Target |
|---|---|
| Text top-k recall on Natural Questions sample | Baseline established before Week 4 retrieval tuning |
| Image/text retrieval sanity set on COCO sample | Qualitative pass plus recall snapshot |
| Average embedding latency on local CPU | Recorded for Week 6 optimization baseline |

## 5. Acceptance Notes

For Week 3, the codebase now contains the embedding engine implementation,
model asset instructions, conversion scripts, and an embedding-focused unit
test suite. Production-model accuracy validation remains a documented follow-up
because the model weights are intentionally not committed.
