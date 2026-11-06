#!/usr/bin/env bash
# Fetches the pretrained YOLOX-Nano model that Visual Traffic bundles and
# rewrites it so flutter_litert can run it. No training is involved.
#
# Needs: curl, python3 with numpy and flatbuffers, and flatc
# (for example: brew install flatbuffers).
#
# Result: assets/models/yolox_nano.tflite
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

MODEL_URL="https://huggingface.co/litert-community/yolox-nano-litert/resolve/main/yolox_nano.tflite"
SCHEMA_URL="https://raw.githubusercontent.com/tensorflow/tensorflow/master/tensorflow/lite/schema/schema.fbs"
# SHA-256 of the file published at MODEL_URL when it was bundled.
ORIGINAL_SHA256="3a621c40141760da2435891093616e4d8cfa8748000c72ced4e536d694f970e4"

echo "Downloading the model and the TensorFlow Lite schema"
curl -fsSL -o "$WORK/original.tflite" "$MODEL_URL"
curl -fsSL -o "$WORK/schema.fbs" "$SCHEMA_URL"

ACTUAL="$(shasum -a 256 "$WORK/original.tflite" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$ORIGINAL_SHA256" ]; then
  echo "The published model changed (sha256 $ACTUAL)." >&2
  echo "Check its license and I/O shape, then update ORIGINAL_SHA256 here." >&2
  exit 1
fi

echo "Generating the schema module"
( cd "$WORK" && flatc --python --gen-object-api --gen-onefile schema.fbs )

echo "Moving the weights into the FlatBuffer"
PYTHONPATH="$WORK" python3 "$ROOT/tools/visual_traffic/inline_tflite_buffers.py" \
  "$WORK/original.tflite" "$ROOT/assets/models/yolox_nano.tflite"

echo "Done: assets/models/yolox_nano.tflite"
