---
license: openrail++
track_downloads: true
language:
- en
- ko
- ja
- ar
- bg
- cs
- da
- de
- el
- es
- et
- fi
- fr
- hi
- hr
- hu
- id
- it
- lt
- lv
- nl
- pl
- pt
- ro
- ru
- sk
- sl
- sv
- tr
- uk
- vi
pipeline_tag: text-to-speech
library_name: coreml
datasets: []
thumbnail: null
tags:
- text-to-speech
- speech
- audio
- tts
- coreml
- ane
- apple-silicon
- flow-matching
- diffusion
- multilingual
- supertonic
base_model:
- Supertone/supertonic-3
---

# **<span style="color:#5DAF8D"> 🧃 supertonic-3: Multilingual Text-to-Speech CoreML </span>**

<style>
img {
 display: inline;
}
</style>

[![Model architecture](https://img.shields.io/badge/Model_Arch-Flow--Matching%20Diffusion-blue#model-badge)](#model-architecture)
| [![Sampling rate](https://img.shields.io/badge/Sample_Rate-44.1kHz-green#model-badge)](#model-details)
| [![Language](https://img.shields.io/badge/Languages-31-blue#model-badge)](#supported-languages)
| [![Discord](https://img.shields.io/badge/Discord-Join%20Chat-7289da.svg)](https://discord.gg/WNsvaCtmDe)
| [![GitHub Repo stars](https://img.shields.io/github/stars/FluidInference/FluidAudio?style=flat&logo=github)](https://github.com/FluidInference/FluidAudio)

On‑device multilingual TTS model converted to Core ML for Apple platforms.
This is a hand‑port of [Supertone Supertonic‑3 v1.7.3](https://huggingface.co/Supertone/supertonic-3)
from ONNX → PyTorch → Core ML, suitable for FluidAudio's TTS pipeline on
macOS/iOS. 31 languages, 44.1 kHz output, flow‑matching diffusion with
classifier‑free guidance (8 denoising steps).

The conversion script is here:
https://github.com/FluidInference/mobius/tree/main/models/tts/supertonic-3/coreml

And the FluidAudio integration is here:
https://github.com/FluidInference/FluidAudio/tree/main/Sources/FluidAudio/TTS/Supertonic3

## Highlights

- **Core ML**: Runs on‑device (ANE + CPU) on Apple Silicon.
- **Multilingual**: 31 languages — see [Supported Languages](#supported-languages).
- **High quality**: 44.1 kHz output via flow‑matching diffusion + ConvNeXt vocoder.
- **Voice styling**: zero‑shot voice style embeddings (single JSON per voice).
- **Performance**: end‑to‑end RTFx ≈ 8.5× on M2 (CoreML), ≈ 17–19× on M2 with current ANE assignment (3 of 4 modules on ANE).
- **Privacy**: No network calls required once models are downloaded.

## Intended Use

- **Batch TTS** for full text segments on macOS/iOS.
- **Local voice synthesis** for note‑taking, accessibility, and creative tools.
- **Embedded TTS** in production apps via the FluidAudio Swift framework.

## Supported Platforms

- macOS 14+ (Apple Silicon recommended)
- iOS 17+

## Model Details

- **Architecture**: Supertonic‑3 v1.7.3 — 4‑stage pipeline:
  1. `text_encoder` — token embeddings → contextual text features `[B, 256, T]`.
  2. `duration_predictor` — predicts utterance duration from text features.
  3. `vector_estimator` — flow‑matching diffusion in latent space
     (8 steps, classifier‑free guidance via batch‑2 duplication, ConvNeXt + cross‑attention to text + style attention).
  4. `vocoder` — ConvNeXt decoder → 44.1 kHz waveform.
- **Output audio**: 44.1 kHz mono, Float32 PCM.
- **Languages**: 31 (see below).
- **Precision**: FP16 weights and activations (mlprogram, iOS 18+ minimum deployment target).
- **Granularity**: vocoder frame ≈ 11.6 ms; latent tick ≈ 69.7 ms.

## Supported Languages

English, Korean, Japanese, Arabic, Bulgarian, Czech, Danish, German, Greek,
Spanish, Estonian, Finnish, French, Hindi, Croatian, Hungarian, Indonesian,
Italian, Lithuanian, Latvian, Dutch, Polish, Portuguese, Romanian, Russian,
Slovak, Slovenian, Swedish, Turkish, Ukrainian, Vietnamese.

## Performance (Apple M2, macOS 26.5, FP16)

| Module                  | Size   | Predict | Compute placement |
| ----------------------- | ------ | ------- | ----------------- |
| duration_predictor      | 1.8 MB | 0.82 ms | CPU (tiny)        |
| text_encoder            | 17 MB  | 2.15 ms | 62 % ANE          |
| vocoder                 | 48 MB  | 1.17 ms | 100 % ANE         |
| vector_estimator (fp16) | 122 MB | 9.29 ms | CPU + GPU (see notes) |
| vector_estimator (int8) | 62 MB  | ~same   | int8 weight-only / fp16 acts; ~10 % lower peak RSS, RMSE ≈ 0.016 vs FP16 |

End‑to‑end on M2: ≈ 0.74 s to synthesize 6.32 s of audio for a single English
sentence (RTFx ≈ 8.5×), 8 denoising steps. Output verified against
FluidAudio Parakeet TDT ASR.

**Note on `vector_estimator`**: 100 % of its ops are ANE‑eligible after
the float‑mask + precompute refactor, but Apple's ANECCompile currently
returns opaque error 11 on this graph and silently falls back to CPU/GPU.
See `coreml/trials.md` in the conversion repo for the full investigation.

## Files

Both `.mlpackage` (Core ML source bundle, includes weights + spec) and the
precompiled `.mlmodelc` (ready for direct `MLModel(contentsOf:)` load) are
shipped — use `.mlmodelc` to skip the on‑device compile step on first load.

- `TextEncoder.mlpackage` / `TextEncoder.mlmodelc`               — fixed `T=128` text input.
- `DurationPredictor.mlpackage` / `DurationPredictor.mlmodelc`   — fixed `T=128` text input.
- `VectorEstimator.mlpackage` / `VectorEstimator.mlmodelc`       — `latent.L` and `text.T` as RangeDim(17..512), FP16 weights (122 MB).
- `VectorEstimator_int8.mlpackage` / `VectorEstimator_int8.mlmodelc` — same model, **int8 weight-only** (per-channel symmetric) + FP16 activations (62 MB; ~10 % lower peak RSS, RMSE ≈ 0.016 vs FP16).
- `Vocoder.mlpackage` / `Vocoder.mlmodelc`                       — `latent.L_ttl` as RangeDim(4..512).
- `tts.json`                     — token / text frontend configuration.
- `unicode_indexer.json`         — Unicode → token id mapping (multilingual frontend).
- `voice_styles/`                — 10 voice style embeddings, one JSON per voice (`F1`-`F5` female, `M1`-`M5` male). See [Voices](#voices).
- `manifest.json`                — file inventory (sha256 + sizes) for both `.mlpackage` and `.mlmodelc`.
- `infer.py`                     — minimal self-contained Python demo (loads `.mlmodelc` / `.mlpackage` directly).
- `requirements.txt`             — Python deps for `infer.py` (`coremltools`, `numpy`, `soundfile`).

## Voices

10 zero-shot voice styles ship under `voice_styles/`, one JSON per voice. Pick
the path of the one you want at synthesis time (`--voice-style` in `infer.py`,
or `Supertonic3VoiceStyle.load(from:)` in Swift). They are caller-supplied, so
there is no separate selection step in the model itself.

| Voice | Gender | File |
|-------|--------|------|
| F1 | Female | `voice_styles/F1.json` |
| F2 | Female | `voice_styles/F2.json` |
| F3 | Female | `voice_styles/F3.json` |
| F4 | Female | `voice_styles/F4.json` |
| F5 | Female | `voice_styles/F5.json` |
| M1 | Male | `voice_styles/M1.json` |
| M2 | Male | `voice_styles/M2.json` |
| M3 | Male | `voice_styles/M3.json` |
| M4 | Male | `voice_styles/M4.json` |
| M5 | Male | `voice_styles/M5.json` |

All 10 are the upstream Supertonic-3 reference styles, copied verbatim from
[Supertone/supertonic-3](https://huggingface.co/Supertone/supertonic-3/tree/main/voice_styles).

## Voices

10 zero-shot voice styles ship under `voice_styles/`, one JSON per voice. Pick
the path of the one you want at synthesis time (`--voice-style` in `infer.py`,
or `Supertonic3VoiceStyle.load(from:)` in Swift). They are caller-supplied, so
there is no separate selection step in the model itself.

| Voice | Gender | File |
|-------|--------|------|
| F1 | Female | `voice_styles/F1.json` |
| F2 | Female | `voice_styles/F2.json` |
| F3 | Female | `voice_styles/F3.json` |
| F4 | Female | `voice_styles/F4.json` |
| F5 | Female | `voice_styles/F5.json` |
| M1 | Male | `voice_styles/M1.json` |
| M2 | Male | `voice_styles/M2.json` |
| M3 | Male | `voice_styles/M3.json` |
| M4 | Male | `voice_styles/M4.json` |
| M5 | Male | `voice_styles/M5.json` |

All 10 are the upstream Supertonic-3 reference styles, copied verbatim from
[Supertone/supertonic-3](https://huggingface.co/Supertone/supertonic-3/tree/main/voice_styles).

## Usage

### Quick test (Python)

For the curious / for sanity checking, this repo ships a small self‑contained
script `infer.py` that loads all four modules directly via `coremltools` and
writes a 44.1 kHz WAV. No external repo clone required.

```bash
# 1. Download the repo (e.g. via huggingface_hub or `git lfs clone`).
git lfs clone https://huggingface.co/FluidInference/supertonic-3-coreml
cd supertonic-3-coreml

# 2. Install the 3 deps (macOS, Python 3.11+ recommended).
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 3. Synthesize.
python infer.py "Hello, world." --voice-style voice_styles/M1.json -o hello.wav
python infer.py "Bonjour le monde." --lang fr --voice-style voice_styles/M1.json -o fr.wav

# Use the int8-quantized VectorEstimator (62 MB instead of 122 MB).
python infer.py "Hello, int8 build." --vector-estimator VectorEstimator_int8.mlpackage -o int8.wav

# Optional: pick a compute unit explicitly.
python infer.py "Test" --compute-units CPU_AND_NE -o ne.wav
```

The Python script loads `.mlpackage` (which is what `coremltools` accepts);
the `.mlmodelc` bundles are for direct Swift / Objective‑C use
(`MLModel(contentsOf:)`) where they skip the on‑device compile step.

### Production (Swift / FluidAudio)

For production use, the FluidAudio Swift framework handles model loading,
text frontend, batching, chunking, and the diffusion / vocoder loop.

#### Swift (FluidAudio)

```swift
import AVFoundation
import FluidAudio

Task {
    // Download and load Supertonic-3 models (first run only)
    let models = try await Supertonic3Models.downloadAndLoad()

    // Initialize the TTS manager
    let tts = Supertonic3Manager(config: .default)
    try await tts.initialize(models: models)

    // Synthesize speech for some text with a voice style
    let style = try VoiceStyle.load(path: "voice_styles/M1.json")
    let audio = try await tts.synthesize(text: "Hello, world.", style: style)

    // audio.samples is 44.1 kHz Float32 PCM in [-1, 1]
    try AudioWriter.writeWav(audio.samples, sampleRate: 44_100, to: "hello.wav")

    tts.cleanup()
}
```

For more examples (including CLI usage and benchmarking), see the FluidAudio
repository: https://github.com/FluidInference/FluidAudio

## Limitations

- 44.1 kHz output is high quality but heavier than 16/22.05 kHz TTS — plan
  for the bandwidth and storage cost.
- `vector_estimator` currently runs on CPU + GPU instead of ANE due to an
  Apple‑side ANE compiler limitation (see [Performance](#performance-apple-m2-macos-265-fp16)).
- Text frontend currently uses fixed `T=128` token windows; longer text
  must be segmented by the caller.

## License

OpenRAIL‑M (inherited from upstream [Supertone/supertonic-3](https://huggingface.co/Supertone/supertonic-3)).
The Core ML conversion tooling and FluidAudio integration are MIT‑licensed.
See the [FluidAudio repository](https://github.com/FluidInference/FluidAudio)
for details and usage guidance.
