#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOAD_DIR="$ROOT_DIR/.downloads"
TOOLING_DIR="$ROOT_DIR/.tooling"
FLUTTER_ZIP="$DOWNLOAD_DIR/flutter_macos_arm64_3.44.4-stable.zip"
FLUTTER_DIR="$TOOLING_DIR/flutter"
JRE_TGZ="$DOWNLOAD_DIR/temurin21-jre-macos-aarch64.tar.gz"
JRE_DIR="$TOOLING_DIR/jdk-21.0.11+10-jre"

mkdir -p "$DOWNLOAD_DIR" "$TOOLING_DIR" "$ROOT_DIR/assets/models"

if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  if [[ ! -f "$FLUTTER_ZIP" ]]; then
    curl -L "https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_arm64_3.44.4-stable.zip" -o "$FLUTTER_ZIP"
  fi
  unzip -q "$FLUTTER_ZIP" -d "$TOOLING_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
export HOME="${HOME:-$ROOT_DIR/.home}"
export PUB_CACHE="${PUB_CACHE:-$ROOT_DIR/.pub-cache}"

flutter --version
flutter pub get

if command -v python3 >/dev/null 2>&1; then
  python3 -m pip install --user chromadb
  python3 -m pip install --user cmake
  python3 -m pip install --user pypdfium2
  python3 -m pip install --user kagglehub huggingface_hub timm tensorflow torch torchvision ai-edge-torch
fi

TIKA_JAR="$TOOLING_DIR/tika-server-standard.jar"
if [[ ! -f "$TIKA_JAR" ]]; then
  curl -L "https://repo1.maven.org/maven2/org/apache/tika/tika-server-standard/3.3.1/tika-server-standard-3.3.1.jar" -o "$TIKA_JAR"
fi

TIKA_APP_JAR="$TOOLING_DIR/tika-app.jar"
if [[ ! -f "$TIKA_APP_JAR" ]]; then
  curl -L "https://repo1.maven.org/maven2/org/apache/tika/tika-app/3.3.1/tika-app-3.3.1.jar" -o "$TIKA_APP_JAR"
fi

if [[ ! -x "$JRE_DIR/Contents/Home/bin/java" ]]; then
  if [[ ! -f "$JRE_TGZ" ]]; then
    curl -L "https://api.adoptium.net/v3/binary/latest/21/ga/mac/aarch64/jre/hotspot/normal/eclipse?project=jdk" -o "$JRE_TGZ"
  fi
  tar -xzf "$JRE_TGZ" -C "$TOOLING_DIR"
fi

cat <<'MSG'

Strict environment bootstrap complete.

Still required:
- Download or convert real TensorFlow Lite model files at:
  assets/models/bert_text_encoder.tflite
  assets/models/mobileclip_image_encoder.tflite
- Start Chroma DB before running the app:
  $HOME/Library/Python/3.9/bin/chroma run --path .chroma --host 127.0.0.1 --port 8000
- Start Apache Tika when native bindings are wired:
  .tooling/jdk-21.0.11+10-jre/Contents/Home/bin/java -jar .tooling/tika-server-standard.jar --host 127.0.0.1 --port 9998
- The macOS platform channel uses pypdfium2 for PDFium extraction and tika-app.jar for Tika extraction.

Run tests:
  flutter test --coverage --no-pub
MSG
