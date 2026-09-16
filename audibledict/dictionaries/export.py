"""Export jobs for externally generated dictionary recordings."""

import json
import sqlite3
from pathlib import Path


def export_audio(
    library: Path,
    output: Path,
    kind: str,
    accent: str | None = None,
    fallback: bool = False,
) -> int:
    """Export contextual JSONL jobs with deterministic relative audio filenames.

    Args:
        library (Path): Imported library folder.
        output (Path): Destination JSONL file.
        kind (str): examples or headwords.
        accent (str | None): Headword accent, us or uk; None exports both.
            Ignored for examples, which use English without a specified accent.
        fallback (bool): Write output paths under audio/fallback.

    Returns:
        int: Number of jobs written. No audio is synthesized.
    """
    db = sqlite3.connect(
        f"{(library / 'dictionary.sqlite').resolve().as_uri()}?mode=ro", uri=True
    )
    db.row_factory = sqlite3.Row
    if kind == "examples":
        accents = [None]
        rows = db.execute("""SELECT x.*, e.source, e.source_id, e.headword, e.pronunciations
                             FROM examples x JOIN entries e ON e.id=x.entry_id ORDER BY x.id""")
    else:
        accents = [accent] if accent else ["us", "uk"]
        rows = db.execute("""SELECT audio_id AS id, id AS entry_id, source_id, source,
                             headword, headword AS text, pronunciations FROM entries ORDER BY audio_id""")
    output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with output.open("w", encoding="utf-8") as stream:
        for row in rows:
            job = dict(row)
            job["pronunciations"] = json.loads(job["pronunciations"])
            job["kind"] = kind
            for voice_accent in accents:
                directory = f"audio/{'fallback/' if fallback else ''}{job['source']}"
                job["language"] = "en"
                if voice_accent:
                    directory += f"/{voice_accent}"
                    job["accent"] = voice_accent
                    job["language"] = "en-US" if voice_accent == "us" else "en-GB"
                job["audio_path"] = f"{directory}/{job['id']}.caf"
                stream.write(json.dumps(job, ensure_ascii=False) + "\n")
                count += 1
    db.close()
    return count
