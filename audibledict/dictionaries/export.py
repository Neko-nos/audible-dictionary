"""Export jobs for externally generated dictionary recordings."""

import json
import sqlite3
from pathlib import Path


def export_audio(
    library: Path, output: Path, kind: str, accent: str, fallback: bool = False
) -> int:
    """Export contextual JSONL jobs with deterministic relative audio filenames.

    Args:
        library (Path): Imported library folder.
        output (Path): Destination JSONL file.
        kind (str): examples or headwords.
        accent (str): us or uk.
        fallback (bool): Write output paths under audio/fallback.

    Returns:
        int: Number of jobs written. No audio is synthesized.
    """
    db = sqlite3.connect(
        f"{(library / 'dictionary.sqlite').resolve().as_uri()}?mode=ro", uri=True
    )
    db.row_factory = sqlite3.Row
    if kind == "examples":
        rows = db.execute("""SELECT x.*, e.source, e.source_id, e.headword, e.pronunciations
                             FROM examples x JOIN entries e ON e.id=x.entry_id ORDER BY x.id""")
    else:
        rows = db.execute("""SELECT audio_id AS id, id AS entry_id, source_id, source,
                             headword, headword AS text, pronunciations FROM entries ORDER BY audio_id""")
    output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with output.open("w", encoding="utf-8") as stream:
        for row in rows:
            job = dict(row)
            job["pronunciations"] = json.loads(job["pronunciations"])
            job.update(
                {
                    "kind": kind,
                    "accent": accent,
                    "language": "en-US" if accent == "us" else "en-GB",
                    "audio_path": f"audio/{'fallback/' if fallback else ''}{job['source']}/{accent}/{job['id']}.mp4",
                }
            )
            stream.write(json.dumps(job, ensure_ascii=False) + "\n")
            count += 1
    db.close()
    return count
