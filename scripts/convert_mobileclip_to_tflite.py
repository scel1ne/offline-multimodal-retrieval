#!/usr/bin/env python3
import argparse
from pathlib import Path

import ai_edge_torch
import torch
import torch.nn as nn
import torch.nn.functional as F

import mobileclip


class MobileClipImageEncoder(nn.Module):
    def __init__(self, model: nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        features = self.model.encode_image(image, normalize=False)
        return F.normalize(features, dim=-1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--checkpoint",
        default=".downloads/mobileclip-s0/mobileclip_s0.pt",
        help="Official Apple MobileCLIP-S0 PyTorch checkpoint.",
    )
    parser.add_argument(
        "--output",
        default="assets/models/mobileclip_image_encoder.tflite",
        help="Destination TensorFlow Lite image encoder.",
    )
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
    sample_image = torch.zeros(1, 3, 256, 256)

    edge_model = ai_edge_torch.convert(image_encoder, (sample_image,))
    output.parent.mkdir(parents=True, exist_ok=True)
    edge_model.export(str(output))
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
