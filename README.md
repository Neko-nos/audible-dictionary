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
