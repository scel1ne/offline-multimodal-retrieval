#!/usr/bin/env python3
from pathlib import Path

import numpy as np
import tensorflow as tf

import onnx2tf.onnx2tf as converter
import onnx2tf.utils.common_functions as common_functions


def _local_test_image_data() -> np.ndarray:
    return np.zeros((1, 256, 256, 3), dtype=np.float32)


def main() -> int:
    onnx_path = Path(".downloads/mobileclip-s0/mobileclip_image_encoder.onnx")
    saved_model_dir = Path(".downloads/mobileclip-s0/tf_saved_model")
    tflite_path = Path("assets/models/mobileclip_image_encoder.tflite")
    if not onnx_path.exists():
        raise FileNotFoundError(onnx_path)

    common_functions.download_test_image_data = _local_test_image_data
    converter.download_test_image_data = _local_test_image_data
    converter.convert(
        input_onnx_file_path=str(onnx_path),
        output_folder_path=str(saved_model_dir),
        not_use_onnxsim=True,
        disable_strict_mode=True,
        keep_ncw_or_nchw_or_ncdhw_input_names=["image"],
    )

    converter_model = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    converter_model.optimizations = []
    tflite_model = converter_model.convert()
    tflite_path.parent.mkdir(parents=True, exist_ok=True)
    tflite_path.write_bytes(tflite_model)
    print(tflite_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
