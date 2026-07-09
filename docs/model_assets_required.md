# Model Assets Required

**Author:** Celine Song
**Status:** Week 3 supporting note
**Last updated:** 2026-07-09

The production model weights are intentionally not committed to Git because
they are large binary artifacts and must be downloaded from their official
sources under their own license terms.

## Expected Local Files

Place these files under `assets/models/` before running production embedding
inference:

| File | Purpose | Source |
|---|---|---|
| `bert_text_encoder.tflite` | Text embedding encoder for local CPU inference | TensorFlow Lite / BERT-family model export |
| `mobileclip_image_encoder.tflite` | Portable image embedding encoder | Apple MobileCLIP export converted to TensorFlow Lite |
| `mobileclip_s0_image.mlpackage/` | macOS CoreML image embedding package | Apple MobileCLIP-S0 release |

## Development Fallback

The committed app remains testable without the model binaries. If the real
model files are absent, the embedding engine falls back to deterministic local
text hashing and Dart image features so tests and offline demos do not require
network access.

This fallback is for development and validation only. Production accuracy
validation must be rerun after placing the real model files locally.
