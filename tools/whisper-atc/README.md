# Whisper-tiny.en ATC fine-tune toolkit

End-to-end recipe for training an aviation-tuned `whisper-tiny.en` that AvareX
can use as its offline Transcribe engine. The on-phone code in this repo
(`lib/transcribe/whisper_*`) already knows how to load a `ggml-tiny.en.bin`
file — the job here is producing one that's accurate on ATC audio.

The output of this pipeline is a single `~33 MB` file you can drop into the app
in one of three ways (see [§ Deployment](#deployment) below).

---

## Why fine-tune

Stock `whisper-tiny.en` was trained mostly on TED-style read speech and
podcasts. It has effectively never heard:

- Heavy radio-band compression (300–3000 Hz, distorted).
- ATC phraseology ("cleared to land", "fly heading 270", "squawk 1200").
- Numeric callsigns spoken phonetically ("November one two three four").
- Pilot intercom with engine drone at 100 dB SPL.

The result is the "Thanks for watching" hallucination loop you saw on first
test. Fine-tuning on ~8 k aviation audio/transcript pairs from
[`jacktol/ATC-ASR-Dataset`](https://huggingface.co/datasets/jacktol/ATC-ASR-Dataset)
typically drops Word Error Rate from ~50 % to ~12-18 % on held-out ATC —
enough that AvareX's Transcribe screen becomes genuinely useful in the cockpit.

---

## What's in this folder

| File | Purpose |
|---|---|
| `train_whisper_atc_tiny.ipynb` | Colab-ready notebook. Click "Run all" on a T4. |
| `requirements.txt` | Python deps (Colab pre-pins the same versions). |
| `convert_to_ggml.sh` | Post-training: HF checkpoint → `ggml-tiny.en.bin` + quantize. |
| `README.md` | You are here. |

The notebook covers steps 1–10 (data, training, eval). The shell script covers
steps 11–12 (convert, quantize). Use the notebook for both, or split if you
prefer training in Colab and converting locally on a beefier laptop.

---

## Prerequisites

1. A **HuggingFace account** with a read access token
   (Settings → Access Tokens → New token, scope "read"). Needed to download the
   dataset.
2. A **GPU**. Options, cheapest first:
   - Free Colab T4 (15 GB VRAM). Runs the recipe in ~1 hour.
   - Local 8 GB+ NVIDIA card. Same code path, just replace cells with `python`.
   - Rented A100 on Runpod / Vast.ai if you want faster iteration (~$1/h).
3. ~5 GB free disk where you train.

You do **not** need your own audio for this initial run — the public dataset
is enough to get a useful model. Adding your own ATC recordings later is a
matter of concatenating them into the train split.

---

## Step-by-step

### 1. Launch the notebook

- Open [colab.research.google.com](https://colab.research.google.com).
- File → Upload notebook → pick `train_whisper_atc_tiny.ipynb` from this folder.
- Runtime → Change runtime type → **T4 GPU** → Save.
- Run cells top to bottom. The notebook will prompt you for your HF token
  in cell 2.

Expected runtime breakdown on T4:

| Phase | Time |
|---|---|
| Install deps | ~2 min |
| Download dataset | ~2 min |
| Preprocess (cache mel features) | ~8 min |
| Train 4 epochs (~1000 steps) | 45-70 min |
| Eval + save | ~3 min |

Total: roughly **1 to 1.5 hours**.

### 2. Verify training

The notebook logs WER every 200 steps. A good run looks like:

```
step  200  loss 1.21  eval_wer 38.4
step  400  loss 0.87  eval_wer 22.7
step  600  loss 0.71  eval_wer 16.2
step  800  loss 0.65  eval_wer 13.8
step 1000  loss 0.62  eval_wer 13.1   <- best
```

If WER **goes up** after step ~800, you're overfitting — the trainer is
configured with `load_best_model_at_end=True`, so it'll automatically restore
the best checkpoint when training finishes. No action needed.

If WER **stays near 100 %** for 200+ steps, something is wrong. The two
common causes are a tokenizer/language mismatch (re-run cell 4) and a wildly
wrong learning rate (try `5e-6` instead of `1e-5`).

### 3. Convert to ggml + quantize

The notebook does this in its last cells. If you'd rather run it locally
(faster on a real machine), download the `whisper-tiny-en-atc-final/` folder
from Colab and run:

```bash
bash convert_to_ggml.sh /path/to/whisper-tiny-en-atc-final ./out
```

You'll end up with `./out/ggml-tiny.en.bin` at ~33 MB (q5_1-quantized).
That single file is what AvareX consumes.

---

## Deployment

Three ways to get `ggml-tiny.en.bin` onto a phone running AvareX, easiest first.

### A. In-app "Import from file" (for testing, no host needed)

In Transcribe → AI Voice Pack, tap **Import from file…**. Pick the `.bin`
on the phone's storage and choose which slot to install it into (Compact ↔
`tiny.en` or Standard ↔ `base.en`). The file is copied into the app's
private model directory and the row flips to *Installed*. Subsequent app
restarts pick it up automatically.

To get the file *onto* the phone:

- **Android**: copy via USB MTP, or download in a browser to `/Download`,
  or `adb push` straight into the app dir.
- **iOS**: drag into Files app via cable, or share into AvareX via AirDrop
  → Files → Browse.

This is the right path while you're iterating on the fine-tune.

### B. Host on your own URL (for distribution)

Once you're happy with a model, host the file (GitHub Release, S3, your own
nginx, doesn't matter), then add the URL to `_customDownloadUrls` in
`lib/transcribe/whisper_model_manager.dart`:

```dart
static const Map<WhisperModel, String> _customDownloadUrls = {
  WhisperModel.tinyEn:
    'https://github.com/apps4av/avarex/releases/download/whisper-atc-v1/ggml-tiny.en.bin',
};
```

Push a new app build. The existing **Download** button on the Compact tile
will pull your file instead of the stock HuggingFace one. The UI flow,
progress reporting, atomic rename, cancel handling — all reused as-is.

Bump the URL (`...-v2`, `...-v3`, ...) every time you re-train, and have
users delete + re-download from the voice-pack tile to upgrade.

### C. Ship in app assets (for offline-from-day-one)

Bundle `ggml-tiny.en.bin` in `assets/`, extract on first launch into the
model dir, mark installed. Adds ~33 MB to the APK/IPA. Not currently wired
up — if you want this, ask and I'll add it; otherwise B is almost always
the better choice because you can update without a store release.

---

## Tweaking the recipe

### "I have my own ATC recordings"

Two ways:

1. **Append to the public dataset** before fine-tuning. Easiest:

   ```python
   from datasets import Dataset, concatenate_datasets, Audio
   my_extra = Dataset.from_dict({
       "audio": ["/path/clip_01.wav", "/path/clip_02.wav", ...],
       "text": ["cessna 123 cleared to land runway 27", ...],
   }).cast_column("audio", Audio(sampling_rate=16_000))
   train = concatenate_datasets([raw["train"], my_extra]).shuffle(seed=42)
   ```

   Drop that into the notebook between cells 3 and 6.

2. **Continue training from this fine-tune** on a second pass. Save the
   model at the end of run 1, then re-run the notebook with `MODEL_ID =
   "./whisper-tiny-en-atc-final"` and a smaller LR (`5e-6`).

### "Accuracy isn't good enough, can I move up to base.en?"

Yes. Edit one cell:

```python
MODEL_ID = "openai/whisper-base.en"
```

Everything else stays the same. Training takes ~2× longer; inference on
phone takes ~2-3× longer. Expected WER on the ATC test set drops to roughly
9-12 %. The downstream conversion script auto-detects the model and produces
`ggml-base.en.bin` instead — same deployment patterns apply.

### "I want to also train on ATCO2 / ATCOSIM / LiveATC scraping"

Just keep concatenating dataset shards. More data = better, up to a point;
past ~50 hours you'll want to unfreeze the encoder (drop the
`p.requires_grad = False` loop in cell 4) to use all that volume.

---

## Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| WER stays at 100 % | Tokenizer / language mismatch | Re-run the cell that builds `WhisperProcessor` with `language="english", task="transcribe"` |
| Loss → NaN early | LR too high | Drop `learning_rate` to `5e-6`, bump `warmup_steps` to 500 |
| OOM on T4 | Batch too big | `per_device_train_batch_size=16`, `gradient_accumulation_steps=2` |
| Eval WER good, on-phone garbage | Conversion grabbed wrong checkpoint | Check `trainer.state.best_model_checkpoint` and convert from that dir |
| Hallucinates on real cockpit audio | No augmentation in training | Don't skip the `audiomentations` cell |
| Stuck on first epoch overnight | Colab disconnected, lost session | Use Colab Pro ($10/mo) for 24-h sessions, or train locally |

---

## What this does NOT do

- **No streaming model**. Whisper is fundamentally chunk-based; AvareX
  chunks ATC into ~6 s segments via its amplitude VAD and feeds whole
  segments. This is correct and matches what whisper.cpp itself does.
- **No callsign biasing**. Whisper.cpp supports an `initial_prompt` but
  `whisper_ggml_plus` doesn't expose it. If you find you need callsign
  biasing on top of the fine-tune, that's a separate ~50-line patch to
  the plugin (or PR upstream).
- **No native iOS NPU / Android NNAPI acceleration**. The plugin is CPU
  whisper.cpp only. tiny.en at q5_1 is fast enough on CPU; medium/large
  would need a different runtime.

---

## License notes

- `whisper-tiny.en` is MIT (OpenAI).
- `jacktol/ATC-ASR-Dataset` is MIT per its model card.
- Therefore your fine-tuned `ggml-tiny.en.bin` is MIT — safe to host and
  bundle commercially.
- If you later mix in **ATCO2** or **ATCOSIM**, re-check their licenses
  (ATCO2 in particular is research-licensed).
