#!/usr/bin/env python3
import argparse
from pathlib import Path

import torch
import torch.nn as nn
import torch.nn.functional as F

import mobileclip


class MobileClipImageEncoder(nn.Module):
    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        return F.normalize(self.model.encode_image(image, normalize=False), dim=-1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--checkpoint", default=".downloads/mobileclip-s0/mobileclip_s0.pt")
    parser.add_argument("--output", default=".downloads/mobileclip-s0/mobileclip_image_encoder.onnx")
    args = parser.parse_args()

    checkpoint = Path(args.checkpoint)
    output = Path(args.output)
    if not checkpoint.exists():
        raise FileNotFoundError(checkpoint)

    model, _, _ = mobileclip.create_model_and_transforms(
        "mobileclip_s0",
        pretrained=str(checkpoint),
        device="cpu",
    )
    image_encoder = MobileClipImageEncoder(model).eval()
    sample = torch.zeros(1, 3, 256, 256)
    output.parent.mkdir(parents=True, exist_ok=True)

    torch.onnx.export(
        image_encoder,
        sample,
        str(output),
        input_names=["image"],
        output_names=["embedding"],
        opset_version=17,
        dynamic_axes=None,
    )
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
