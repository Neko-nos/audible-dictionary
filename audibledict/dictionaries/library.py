"""Import dictionary entries into a local searchable library."""

import sqlite3
from pathlib import Path

from audibledict.dictionaries.bundles import entries
from audibledict.dictionaries.parser import parse_entry


def import_library(bundles: dict[str, Path], output: Path) -> None:
    """Build a local search library without modifying installed dictionaries.

    Args:
        bundles (dict[str, Path]): Supported source bundles.
        output (Path): Library folder. Existing audio is retained on reimport.
    """
    output.mkdir(parents=True, exist_ok=True)
    # A completed database replaces the previous index only after a successful import.
    pending = output / "dictionary.pending.sqlite"
    db = sqlite3.connect(pending)
    with db:
        db.executescript("""
            DROP TABLE IF EXISTS examples;
            DROP TABLE IF EXISTS aliases;
            DROP TABLE IF EXISTS entries;
            DROP TABLE IF EXISTS dictionaries;
            CREATE TABLE dictionaries (source TEXT PRIMARY KEY, resource_path TEXT, css TEXT);
            CREATE TABLE entries (id TEXT PRIMARY KEY, source TEXT, source_id TEXT,
                headword TEXT, search_key TEXT, audio_id TEXT, html TEXT);
            CREATE TABLE aliases (term TEXT, entry_id TEXT, PRIMARY KEY (term, entry_id));
            CREATE TABLE examples (id TEXT PRIMARY KEY, entry_id TEXT,
                text TEXT, needs_review INTEGER);
            CREATE INDEX entries_reference ON entries(source, source_id);
            CREATE INDEX examples_entry ON examples(entry_id);
        """)
        for source, bundle in sorted(bundles.items()):
            resources = bundle / "Contents/Resources"
            sources = ("WISDOM", "WISDOM_JE") if source == "WISDOM" else (source,)
            css = (resources / "DefaultStyle.css").read_text()
            db.executemany(
                "INSERT INTO dictionaries VALUES (?, ?, ?)",
                ((name, str(resources), css) for name in sources),
            )
            counts = dict.fromkeys(sources, 0)
            for root in entries(resources / "Body.data"):
                entry, examples, aliases = parse_entry(source, root)
                db.execute(
                    "INSERT INTO entries VALUES (:id,:source,:source_id,:headword,:search_key,:audio_id,:html)",
                    entry,
                )
                db.executemany(
                    "INSERT OR IGNORE INTO examples VALUES (:id,:entry_id,:text,:needs_review)",
                    examples,
                )
                db.executemany(
                    "INSERT INTO aliases VALUES (?, ?)",
                    ((term, entry["id"]) for term in aliases),
                )
                counts[entry["source"]] += 1
            for name, count in counts.items():
                print(f"{name}: imported {count:,} entries", flush=True)
    db.close()
    pending.replace(output / "dictionary.sqlite")
