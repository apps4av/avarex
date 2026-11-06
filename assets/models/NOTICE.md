# Bundled model notices

## yolox_nano.tflite

- Model: YOLOX-Nano, trained on COCO 2017 by Megvii (https://github.com/Megvii-BaseDetection/YOLOX).
- Conversion: FP16 LiteRT/TFLite re-authoring by litert-community
  (https://huggingface.co/litert-community/yolox-nano-litert). Weights are unchanged.
- Repackaging: the published file keeps its weights after the FlatBuffer, which
  flutter_litert cannot read. `tools/visual_traffic/fetch_model.sh` moves them
  inside the file. The model output is identical.
- License: Apache License 2.0 (https://www.apache.org/licenses/LICENSE-2.0).
- Used by the Visual Traffic feature to confirm that a moving sky target is an
  airplane. The file is a swappable asset: any model with the same I/O contract
  (input `[1,416,416,3]` BGR 0-255, output `[1,3549,85]`) can replace it.
