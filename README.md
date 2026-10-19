# Audible Dictionary

A macOS app for looking up English and Japanese words in **WISDOM English–Japanese
and Japanese–English** and **Oxford Dictionary of English (ODE)**, with spoken
pronunciations and examples in the English dictionaries.

## Setup

Download both dictionaries in Apple’s Dictionary app, then run from this project’s folder:

```console
uv run audibledict/dictionaries/cli.py import
bash scripts/build.sh
```

Open **`build/Audible Dictionary.app`**.

## Use

- Search for a word, then click **US/UK** or an English example to hear it.
- Use **File → Open Library…** (⌘O) to choose another dictionary library.

Missing recordings are generated on your Mac when clicked and saved for later use.

## Generate recordings

Export speech jobs on your Mac:

```console
uv run audibledict/dictionaries/cli.py export --output exports/examples.jsonl
uv run audibledict/dictionaries/cli.py export --kind headwords --output exports/headwords.jsonl
```

```console
export CUDA_VISIBLE_DEVICES=0,1
uv sync --extra tts
uv run audibledict/tts/breeze/cli.py exports/examples.jsonl --output /path/to/audio
uv run audibledict/tts/breeze/cli.py exports/headwords.jsonl --kind headwords --output /path/to/audio
```

ASR checks allow 5% character error and up to 5 generation rounds; adjust these
with `--max-cer` and `--max-attempts`. To replace remaining failures with Kokoro:

```console
uv run audibledict/tts/fallback/regenerate.py /path/to/audio/asr-examples.jsonl
uv run audibledict/tts/fallback/regenerate.py /path/to/audio/asr-headwords.jsonl
```

Kokoro runs once and keeps recordings that still fail ASR.

## Compress and transfer recordings

On Ubuntu, create independent ALAC/CAF ZIPs of about 1 GB each:

```console
uv run scripts/compress_audio.py /path/to/audio -o audio-alac
```

On your Mac, download and convert the ZIPs automatically to 32 kbit/s Opus/CAF:

```console
uv run scripts/extract_audio.py 'user@host:/path/to/audio-alac/*.zip' -o build/audio
```

Uses your normal SSH configuration. Only one ZIP is downloaded at a time.
Recordings are saved directly under `build/audio/ODE/` and `build/audio/WISDOM/`.
