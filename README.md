# Audible Dictionary

Look up English words in **WISDOM English–Japanese** and **Oxford Dictionary of English (ODE)**, and play imported US/UK pronunciation and example audio offline.

## Setup

Requires macOS 14+, Swift 6.1+ (Xcode Command Line Tools), and uv with Python 3.10+.
Download both dictionaries in Dictionary.app’s settings, then run:

```console
uv run scripts/dictionaries.py import
bash scripts/build.sh
```

Open **`build/Audible Dictionary.app`**. It loads `build/Library` automatically;
use **File → Open Library…** (⌘O) to choose another library.
To update the library, rerun the import and reopen it in the app.

## Search

Type a word or prefix and select a result. Filter by **All**, **WISDOM**, or **ODE**.
Click **US/UK** for headword audio or an example’s audio button. The accent picker
controls example playback. Press **⌘.** to stop.

## Prepare audio

Export synthesis jobs:

```console
uv run scripts/dictionaries.py export --accent us --output exports/examples-us.jsonl
uv run scripts/dictionaries.py export --kind headwords --accent us --output exports/headwords-us.jsonl
```

Use `--accent uk` for British English. Add `--fallback` for fallback recordings.

Copy the JSONL files to your synthesis machine. Generate each record’s `text` and
save AAC-encoded MP4 audio at `audio_path`, keeping its `id` unchanged. Review
examples marked `needs_review`; `context` and `pronunciations` help choose the wording
and pronunciation. The app does not generate audio.

Copy the resulting `audio/` folder beside the `.app` (currently in `build/`):

```text
audio/<dict>/<accent>/<id>.mp4
audio/fallback/<dict>/<accent>/<id>.mp4
```

`<dict>` is `ODE` or `WISDOM`; `<accent>` is `us` or `uk`. The app checks the main
folder first, then the fallback folder. Missing audio disables playback.
Click **Refresh audio** after copying files. Move the `audio/` folder with the app.

Run `uv run scripts/dictionaries.py export --help` for all export options.
