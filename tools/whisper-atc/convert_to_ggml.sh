#!/usr/bin/env bash
# Convert a HuggingFace Whisper checkpoint to a quantized ggml file
# consumable by AvareX's offline Transcribe engine.
#
# Usage:
#   bash convert_to_ggml.sh <hf_checkpoint_dir> <out_dir>
#
# Example:
#   bash convert_to_ggml.sh ./whisper-tiny-en-atc-final ./out
#   -> writes ./out/ggml-tiny.en.bin (~33 MB, q5_1)
#
# The output filename mirrors AvareX's WhisperVoicePackVariant.fileName so
# you can sideload it directly via Transcribe > AI Voice Pack > Import from
# file... with no renaming.

set -euo pipefail

HF_DIR="${1:-}"
OUT_DIR="${2:-./out}"
WHISPER_CPP_REF="${WHISPER_CPP_REF:-master}"
QUANT_TYPE="${QUANT_TYPE:-q5_1}"

if [[ -z "$HF_DIR" ]]; then
    echo "usage: bash convert_to_ggml.sh <hf_checkpoint_dir> [out_dir]" >&2
    exit 1
fi

if [[ ! -d "$HF_DIR" ]]; then
    echo "error: $HF_DIR is not a directory" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
OUT_DIR_ABS="$(cd "$OUT_DIR" && pwd)"
HF_DIR_ABS="$(cd "$HF_DIR" && pwd)"

# --- 1. Get whisper.cpp (conversion script + quantize tool source) ---------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
echo "==> cloning whisper.cpp@${WHISPER_CPP_REF} into $WORK"
git clone --depth 1 --branch "$WHISPER_CPP_REF" \
    https://github.com/ggml-org/whisper.cpp.git "$WORK/whisper.cpp" \
    >/dev/null 2>&1 || git clone --depth 1 \
        https://github.com/ggml-org/whisper.cpp.git "$WORK/whisper.cpp"

# --- 1b. Also clone openai/whisper, the conversion script needs its
# `whisper/assets/mel_filters.npz` asset to derive mel filters.
echo "==> cloning openai/whisper for mel_filters.npz"
git clone --depth 1 https://github.com/openai/whisper.git "$WORK/openai-whisper" \
    >/dev/null

# --- 2. Run the HF -> ggml conversion --------------------------------------
echo "==> converting HuggingFace checkpoint to ggml fp16"
pushd "$WORK/whisper.cpp" >/dev/null
# We deliberately do NOT install whisper.cpp's requirements-coreml.txt: it
# downgrades protobuf to 3.20.1, which breaks transformers' import chain
# whenever TensorFlow is also installed (e.g. on Colab). The conversion
# script only needs torch / numpy / transformers, which the caller should
# already have available.
python3 models/convert-h5-to-ggml.py \
    "$HF_DIR_ABS" \
    "$WORK/openai-whisper" \
    "$WORK/ggml-out"
popd >/dev/null

# whisper.cpp's convert script writes ggml-model.bin into the out dir.
FP16_BIN="$WORK/ggml-out/ggml-model.bin"
if [[ ! -f "$FP16_BIN" ]]; then
    echo "error: conversion did not produce $FP16_BIN" >&2
    ls -la "$WORK/ggml-out" >&2 || true
    exit 1
fi

# --- 3. Build the quantize binary ------------------------------------------
# whisper.cpp renamed the target from 'quantize' to 'whisper-quantize'
# mid-2024. Try the new name first, fall back to the old one so this still
# works against older tags via WHISPER_CPP_REF.
echo "==> building whisper.cpp quantize tool"
pushd "$WORK/whisper.cpp" >/dev/null
cmake -B build -DGGML_NATIVE=OFF >/dev/null
cmake --build build -j --target whisper-quantize --config Release \
    || cmake --build build -j --target quantize --config Release
popd >/dev/null

# Locate the binary - name/path differs across whisper.cpp versions.
QBIN=""
for cand in \
    "$WORK/whisper.cpp/build/bin/whisper-quantize" \
    "$WORK/whisper.cpp/build/bin/quantize" \
    "$WORK/whisper.cpp/build/whisper-quantize" \
    "$WORK/whisper.cpp/build/quantize" \
    "$WORK/whisper.cpp/build/bin/Release/whisper-quantize.exe" \
    "$WORK/whisper.cpp/build/bin/Release/whisper-quantize" \
    "$WORK/whisper.cpp/build/bin/Release/quantize.exe" \
    "$WORK/whisper.cpp/build/bin/Release/quantize"; do
    if [[ -x "$cand" || -f "$cand" ]]; then
        QBIN="$cand"
        break
    fi
done
if [[ -z "$QBIN" ]]; then
    echo "error: could not find compiled quantize binary" >&2
    find "$WORK/whisper.cpp/build" \( -name 'quantize*' -o -name 'whisper-quantize*' \) >&2 || true
    exit 1
fi

# --- 4. Detect model size from HF config -----------------------------------
SIZE=$(python3 - <<PY
import json, os
with open(os.path.join("$HF_DIR_ABS", "config.json")) as f:
    cfg = json.load(f)
# d_model values: 384 = tiny, 512 = base, 768 = small, 1024 = medium, 1280 = large.
m = cfg.get("d_model") or cfg.get("hidden_size") or 0
sizes = {384: "tiny", 512: "base", 768: "small", 1024: "medium", 1280: "large"}
print(sizes.get(m, "tiny"))
PY
)
echo "==> detected base size: $SIZE"

OUT_BIN="$OUT_DIR_ABS/ggml-${SIZE}.en.bin"

# --- 5. Quantize ------------------------------------------------------------
echo "==> quantizing to $QUANT_TYPE -> $OUT_BIN"
"$QBIN" "$FP16_BIN" "$OUT_BIN" "$QUANT_TYPE"

echo
echo "Done."
ls -lh "$OUT_BIN"
echo
echo "Sideload via AvareX > Transcribe > AI Voice Pack > Import from file..."
