# Audible Dictionary

A macOS app for looking up English words in **WISDOM English–Japanese** and
**Oxford Dictionary of English (ODE)**, with spoken pronunciations and examples.

## Setup

Download both dictionaries in Apple’s Dictionary app, then run from this project’s folder:

```console
uv run audibledict/dictionaries/cli.py import
bash scripts/build.sh
```

Open **`build/Audible Dictionary.app`**.

## Use

- Search for a word or prefix and select a result. Filter by dictionary as needed.
- Click **US/UK** to hear a headword in that accent.
- Click an English example to hear it.
- Press **⌘.** to stop playback or cancel generation.
- Use **File → Open Library…** (⌘O) to choose another dictionary library.

Missing headword and example recordings are generated when clicked and saved for later use.

## Export for speech generation

Export jobs for your TTS pipeline:

```console
uv run audibledict/dictionaries/cli.py export --output exports/examples.jsonl
uv run audibledict/dictionaries/cli.py export --kind headwords --output exports/headwords.jsonl
```

Each JSONL record contains four fields: `text` and `accent` are the TTS model inputs;
`id` identifies the recording, and `source` identifies its dictionary (`WISDOM` or `ODE`).

Headwords export both `us` and `uk` accents by default. Examples export one recording,
using `us` for WISDOM and `uk` for ODE.

Construct the destination at generation time from the export kind and record:

- Examples: `audio/<source>/<id>.caf`
- Headwords: `audio/<source>/<accent>/<id>.caf`

For fallback recordings, use `audio/fallback/` in place of `audio/`. Place the
resulting `audio/` folder beside the app (`build/audio/` for the setup above).
