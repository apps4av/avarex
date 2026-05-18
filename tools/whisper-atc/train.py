"""
Fine-tune whisper-tiny.en on jacktol/ATC-ASR-Dataset for AvareX's offline
Transcribe engine.

Usage:
    # On Colab T4 (free):
    !python train.py

    # Locally with an 8 GB+ NVIDIA GPU:
    pip install -r requirements.txt
    python train.py

Outputs:
    ./whisper-tiny-en-atc-final/   HuggingFace checkpoint (best WER)

To get the on-phone-ready file, run convert_to_ggml.sh on that folder
afterwards (or use the matching cells at the end of run_in_colab.ipynb).

The recipe mirrors `jacktol/whisper-large-v3-finetuned-for-ATC`'s public
training notes, scaled down for tiny.en: 4 epochs, LR 1e-5, batch 32, with
Gaussian-noise + pitch-shift augmentation. Encoder frozen so the small
~8 k-sample dataset doesn't catastrophically forget general English.

Configurable via env vars (handy on Colab):
    MODEL_ID            HuggingFace base model. Default openai/whisper-tiny.en
                        Set to "openai/whisper-base.en" to train base.en instead.
    DATASET_ID          HuggingFace dataset name. Default jacktol/ATC-ASR-Dataset
    OUTPUT_DIR          Trainer working dir. Default ./whisper-tiny-en-atc
    FINAL_DIR           Where to save the best checkpoint. Default ./whisper-tiny-en-atc-final
    NUM_EPOCHS          Default 4
    BATCH_SIZE          Per-device train batch. Default 32. Drop to 16 on 8 GB cards.
    LR                  Default 1e-5
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Dict, List, Union

import numpy as np
import torch
from audiomentations import (
    AddGaussianNoise,
    Compose,
    Gain,
    PitchShift,
    TimeStretch,
)
from datasets import Audio, load_dataset
from transformers import (
    Seq2SeqTrainer,
    Seq2SeqTrainingArguments,
    WhisperFeatureExtractor,
    WhisperForConditionalGeneration,
    WhisperProcessor,
    WhisperTokenizer,
)


MODEL_ID = os.environ.get("MODEL_ID", "openai/whisper-tiny.en")
DATASET_ID = os.environ.get("DATASET_ID", "jacktol/ATC-ASR-Dataset")
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", "./whisper-tiny-en-atc")
FINAL_DIR = os.environ.get("FINAL_DIR", "./whisper-tiny-en-atc-final")
NUM_EPOCHS = float(os.environ.get("NUM_EPOCHS", "4"))
BATCH_SIZE = int(os.environ.get("BATCH_SIZE", "32"))
LR = float(os.environ.get("LR", "1e-5"))


def main() -> None:
    assert torch.cuda.is_available(), (
        "No GPU detected. On Colab: Runtime > Change runtime type > T4 GPU. "
        "Locally: install a CUDA build of torch."
    )
    print(f"GPU: {torch.cuda.get_device_name(0)}")
    print(f"Base model: {MODEL_ID}")
    print(f"Dataset:    {DATASET_ID}")

    # ---- 1. Load dataset ----------------------------------------------------
    raw = load_dataset(DATASET_ID)
    raw = raw.cast_column("audio", Audio(sampling_rate=16_000))
    print(raw)

    if "validation" in raw:
        train_split, val_split = raw["train"], raw["validation"]
    elif "test" in raw:
        train_split, val_split = raw["train"], raw["test"]
    else:
        s = raw["train"].train_test_split(test_size=0.05, seed=42)
        train_split, val_split = s["train"], s["test"]
    print(f"train={len(train_split)}  val={len(val_split)}")

    # ---- 2. Model + processor ----------------------------------------------
    # English-only Whisper variants ('.en' suffix) don't have a lang_to_id
    # table in their generation config (they only know English), so passing
    # language='english'/task='transcribe' triggers an AttributeError inside
    # transformers' generate() at eval time. Multilingual variants (no
    # suffix) do need those set explicitly.
    is_english_only = MODEL_ID.endswith(".en")

    feature_extractor = WhisperFeatureExtractor.from_pretrained(MODEL_ID)
    if is_english_only:
        tokenizer = WhisperTokenizer.from_pretrained(MODEL_ID)
        processor = WhisperProcessor.from_pretrained(MODEL_ID)
    else:
        tokenizer = WhisperTokenizer.from_pretrained(
            MODEL_ID, language="english", task="transcribe"
        )
        processor = WhisperProcessor.from_pretrained(
            MODEL_ID, language="english", task="transcribe"
        )

    model = WhisperForConditionalGeneration.from_pretrained(MODEL_ID)
    if not is_english_only:
        model.generation_config.language = "english"
        model.generation_config.task = "transcribe"
    model.generation_config.forced_decoder_ids = None
    model.config.forced_decoder_ids = None
    model.config.suppress_tokens = []

    # Freeze the encoder: the single biggest stability win on small datasets.
    # Drop this loop only when you have >50 h of paired audio.
    for p in model.model.encoder.parameters():
        p.requires_grad = False

    trainable = sum(p.numel() for p in model.parameters() if p.requires_grad)
    total = sum(p.numel() for p in model.parameters())
    print(f"Trainable params: {trainable/1e6:.1f}M of {total/1e6:.1f}M total")

    # ---- 3. Augmentation ---------------------------------------------------
    # Same shape as jacktol/whisper-large-v3-finetuned-for-ATC's recipe.
    augment = Compose([
        AddGaussianNoise(min_amplitude=0.001, max_amplitude=0.012, p=0.5),
        PitchShift(min_semitones=-2, max_semitones=2, p=0.4),
        Gain(min_gain_db=-6, max_gain_db=6, p=0.3),
        TimeStretch(min_rate=0.95, max_rate=1.05, p=0.2),
    ])

    # jacktol/ATC-ASR-Dataset uses 'text' for the transcript column; other
    # public ATC corpora use 'transcription' or 'sentence'. Try common names
    # so this script keeps working if you swap in a different dataset later.
    text_col_candidates = ("text", "transcription", "sentence", "transcript")
    print("Dataset columns:", train_split.column_names)
    text_col = next(
        (c for c in text_col_candidates if c in train_split.column_names),
        None,
    )
    assert text_col is not None, (
        f"No text column found. Expected one of {text_col_candidates}, "
        f"got {train_split.column_names}."
    )
    print(f"Using '{text_col}' as the transcript column.")

    def prepare_batch(batch, *, do_augment: bool):
        audio = batch["audio"]
        samples = audio["array"]
        if do_augment:
            samples = augment(
                samples=samples.astype(np.float32),
                sample_rate=audio["sampling_rate"],
            )
        inputs = feature_extractor(samples, sampling_rate=16_000)
        batch["input_features"] = inputs.input_features[0]
        text = batch[text_col].lower().strip()
        batch["labels"] = tokenizer(text).input_ids
        return batch

    train_ds = train_split.map(
        lambda b: prepare_batch(b, do_augment=True),
        remove_columns=train_split.column_names,
        num_proc=1,
    )
    val_ds = val_split.map(
        lambda b: prepare_batch(b, do_augment=False),
        remove_columns=val_split.column_names,
        num_proc=1,
    )

    # ---- 4. Collator + metric ---------------------------------------------
    @dataclass
    class DataCollatorSpeechSeq2SeqWithPadding:
        processor: Any

        def __call__(
            self,
            features: List[Dict[str, Union[List[int], torch.Tensor]]],
        ):
            input_features = [
                {"input_features": f["input_features"]} for f in features
            ]
            batch = self.processor.feature_extractor.pad(
                input_features, return_tensors="pt"
            )
            label_features = [{"input_ids": f["labels"]} for f in features]
            labels_batch = self.processor.tokenizer.pad(
                label_features, return_tensors="pt"
            )
            labels = labels_batch["input_ids"].masked_fill(
                labels_batch.attention_mask.ne(1), -100
            )
            if (labels[:, 0] == self.processor.tokenizer.bos_token_id).all().item():
                labels = labels[:, 1:]
            batch["labels"] = labels
            return batch

    data_collator = DataCollatorSpeechSeq2SeqWithPadding(processor=processor)

    import evaluate

    wer_metric = evaluate.load("wer")

    def compute_metrics(pred):
        pred_ids = pred.predictions
        label_ids = pred.label_ids
        label_ids[label_ids == -100] = tokenizer.pad_token_id
        pred_str = tokenizer.batch_decode(pred_ids, skip_special_tokens=True)
        label_str = tokenizer.batch_decode(label_ids, skip_special_tokens=True)
        pred_str = [s.lower().strip() for s in pred_str]
        label_str = [s.lower().strip() for s in label_str]
        return {
            "wer": 100.0 * wer_metric.compute(
                predictions=pred_str, references=label_str
            )
        }

    # ---- 5. Train ---------------------------------------------------------
    args = Seq2SeqTrainingArguments(
        output_dir=OUTPUT_DIR,
        per_device_train_batch_size=BATCH_SIZE,
        per_device_eval_batch_size=max(8, BATCH_SIZE // 2),
        gradient_accumulation_steps=1,
        learning_rate=LR,
        warmup_steps=100,
        num_train_epochs=NUM_EPOCHS,
        fp16=True,
        eval_strategy="steps",
        eval_steps=200,
        save_steps=200,
        logging_steps=25,
        save_total_limit=2,
        predict_with_generate=True,
        generation_max_length=225,
        report_to=["tensorboard"],
        load_best_model_at_end=True,
        metric_for_best_model="wer",
        greater_is_better=False,
        push_to_hub=False,
        dataloader_num_workers=2,
    )

    trainer = Seq2SeqTrainer(
        args=args,
        model=model,
        train_dataset=train_ds,
        eval_dataset=val_ds,
        data_collator=data_collator,
        compute_metrics=compute_metrics,
        tokenizer=processor.feature_extractor,
    )

    trainer.train()

    # ---- 6. Save ----------------------------------------------------------
    trainer.save_model(FINAL_DIR)
    processor.save_pretrained(FINAL_DIR)
    print(f"Saved HF checkpoint to {FINAL_DIR}")
    print(f"Best checkpoint chosen: {trainer.state.best_model_checkpoint}")
    print()
    print("Next: run `bash convert_to_ggml.sh", FINAL_DIR, "./out`")


if __name__ == "__main__":
    main()
