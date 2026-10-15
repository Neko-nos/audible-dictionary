"""Export jobs for externally generated dictionary recordings."""

import json
import sqlite3
from pathlib import Path


def export_audio(
    library: Path,
    output: Path,
    kind: str,
    accent: str | None = None,
) -> int:
    """Export JSONL speech inputs with recording IDs and dictionary sources.

    Each record contains text and accent as TTS model inputs, plus id and
    source to identify the recording and its dictionary. The consuming pipeline
    constructs audio paths at generation time.

    Args:
        library (Path): Imported library folder.
        output (Path): Destination JSONL file.
        kind (str): examples or headwords.
        accent (str | None): Speech accent, us or uk. When omitted, headwords
            export both accents; examples use us for WISDOM and uk for ODE.

    Returns:
        int: Number of jobs written. No audio is synthesized.
    """
    db = sqlite3.connect(
        f"{(library / 'dictionary.sqlite').resolve().as_uri()}?mode=ro", uri=True
    )
    db.row_factory = sqlite3.Row
    if kind == "examples":
        rows = db.execute("""SELECT x.id, x.text, e.source
                             FROM examples x JOIN entries e ON e.id=x.entry_id ORDER BY x.id""")
    else:
        rows = db.execute("""SELECT audio_id AS id, headword AS text, source
                             FROM entries WHERE trim(headword) <> '' ORDER BY audio_id""")
    output.parent.mkdir(parents=True, exist_ok=True)
    count = 0
    with output.open("w", encoding="utf-8") as stream:
        for row in rows:
            if kind == "examples":
                accents = [accent or {"WISDOM": "us", "ODE": "uk"}[row["source"]]]
            else:
                accents = [accent] if accent else ["us", "uk"]
            for voice_accent in accents:
                job = {
                    "text": row["text"],
                    "accent": voice_accent,
                    "id": row["id"],
                    "source": row["source"],
                }
                stream.write(json.dumps(job, ensure_ascii=False) + "\n")
                count += 1
    db.close()
    return count
