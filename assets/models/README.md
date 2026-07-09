# Model Assets

Place the production TensorFlow Lite models here before running the Flutter app:

- `bert_text_encoder.tflite`
- `mobileclip_image_encoder.tflite`
- `mobileclip_s0_image.mlpackage`

The app loads these files from this directory through `tflite_flutter`. The files are not committed because model weights must be downloaded from their official sources and verified against their licenses before redistribution.

See `docs/model_assets_required.md` for the source and license status.
