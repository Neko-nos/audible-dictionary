"""Import installed English dictionaries and export audio jobs, without inference."""

import argparse
import hashlib
import json
import plistlib
import re
import sqlite3
import struct
import unicodedata
import xml.etree.ElementTree as ET
import zlib
from collections.abc import Iterator
from pathlib import Path

JAPANESE = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uff66-\uff9f]")
EDITORIAL = re.compile(r"[\[\]/≒…〜～]|\.{3}|_{2,}")
WHITESPACE = re.compile(r"\s+")


def discover(roots: list[Path]) -> dict[str, Path]:
    """Locate the two supported bundles by their identifiers.

    Args:
        roots (list[Path]): Asset directories or individual dictionary bundles.

    Returns:
        dict[str, Path]: Short dictionary names mapped to installed bundles.
    """
    identifiers = {
        "com.apple.dictionary.ODE": "ODE",
        "com.apple.dictionary.ja-en.WISDOM": "WISDOM",
    }
    found = {}
    for root in roots:
        bundles = (
            [root]
            if root.suffix == ".dictionary"
            else sorted(root.rglob("*.dictionary"))
        )
        for bundle in bundles:
            info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
            identifier = info["CFBundleIdentifier"]
            if identifier in identifiers:
                found[identifiers[identifier]] = bundle
    return found


def entries(body: Path) -> Iterator[ET.Element]:
    """Decode length-prefixed XML records from a macOS Body.data file.

    Args:
        body (Path): Installed dictionary body file.

    Yields:
        ET.Element: An entry with its original namespace and markup.
    """
    with body.open("rb") as stream:
        # Apple's block extent excludes the leading 64-byte header.
        stream.seek(0x40)
        limit = 0x40 + struct.unpack("<I", stream.read(4))[0]
        stream.seek(0x60)
        while stream.tell() < limit:
            size = struct.unpack("<I", stream.read(4))[0]
            # Each compressed block has two additional 32-bit header fields.
            data = zlib.decompress(stream.read(size)[8:])
            position = 0
            while position < len(data):
                size = struct.unpack_from("<I", data, position)[0]
                position += 4
                yield ET.fromstring(data[position : position + size])
                position += size


def normalized(text: str) -> str:
    """Return a case-insensitive search key with typographic apostrophes folded.

    Args:
        text (str): A headword or spelling variant.

    Returns:
        str: Unicode-normalized search text.
    """
    return (
        unicodedata.normalize("NFKC", text)
        .lower()
        .replace("’", "'")
        .replace("‘", "'")
        .strip()
    )


def content_id(*parts: str) -> str:
    """Return a stable filename-safe identifier for a contextual audio item.

    Args:
        *parts (str): Audio kind, source identity, and contextual text.

    Returns:
        str: Hex-encoded SHA-256 digest of null-separated fields.
    """
    return hashlib.sha256("\0".join(parts).encode("utf-8")).hexdigest()


def plain_text(node: ET.Element, omit_labels: bool = False) -> str:
    """Collect text while excluding WISDOM's inline Japanese usage labels.

    Args:
        node (ET.Element): Example or definition element.
        omit_labels (bool): Exclude editorial labels from speech text.

    Returns:
        str: Whitespace-normalized text; alternatives remain intact.
    """
    parts = [node.text or ""]
    for child in node:
        classes = child.attrib.get("class", "").split()
        if not (omit_labels and "oup_label" in classes):
            parts.append(plain_text(child, omit_labels))
        parts.append(child.tail or "")
    # Do not inject spaces between inline emphasis and its surrounding letters.
    return WHITESPACE.sub(" ", "".join(parts))


def parse_entry(
    source: str, root: ET.Element
) -> tuple[dict, list[dict], set[str]] | None:
    """Preserve an entry and attach contextual identifiers to English examples.

    Args:
        source (str): WISDOM or ODE.
        root (ET.Element): Original dictionary entry.

    Returns:
        tuple[dict, list[dict], set[str]] | None: Entry, examples and search aliases,
            or None for the Japanese-to-English half of WISDOM.
    """
    namespace = "{http://www.apple.com/DTDs/DictionaryService-1.0.rng}"
    source_id = root.attrib["id"]
    if source == "WISDOM" and not source_id.startswith("WDEJ_"):
        return None
    headword = root.attrib[namespace + "title"]
    entry_id = source + ":" + source_id
    parent = {child: node for node in root.iter() for child in node}
    examples = []
    pronunciations = []
    aliases = {normalized(headword)}
    for node in root.iter():
        classes = node.attrib.get("class", "").split()
        if set(classes) & {"hw", "hv", "subhw", "l", "f", "frm"}:
            alias = normalized(node.attrib.get("normalized", plain_text(node).strip()))
            if alias and not JAPANESE.search(alias):
                aliases.add(alias)
        if "ph" in classes:
            pronunciations.append(
                {
                    "text": plain_text(node).strip(),
                    "label": node.attrib.get(namespace + "pr", ""),
                    "sound_file": node.attrib.get("soundFile", ""),
                }
            )
        if "ex" not in classes:
            continue
        text = plain_text(node, omit_labels=True).strip()
        # Mixed-language explanations must never be spoken with an English voice.
        if not text or JAPANESE.search(text):
            continue
        ancestor = parent[node]
        while ancestor is not root and "id" not in ancestor.attrib:
            ancestor = parent[ancestor]
        sense_id = ancestor.attrib["id"]
        definitions = [
            plain_text(child).strip()
            for child in ancestor.iter()
            if namespace + "def" in child.attrib
            or "df" in child.attrib.get("class", "").split()
        ]
        audio_id = content_id("example", source, source_id, sense_id, text)
        node.set("data-audio-id", audio_id)
        examples.append(
            {
                "id": audio_id,
                "entry_id": entry_id,
                "sense_id": sense_id,
                "text": text,
                "context": " | ".join(dict.fromkeys(definitions)),
                "needs_review": bool(EDITORIAL.search(text)),
            }
        )
    # HTML keeps the original attributes/classes, without XML namespace prefixes
    # that HTML parsers would treat as literal tag names.
    for node in root.iter():
        if node.tag.startswith(namespace):
            node.tag = "div" if node is root else "span"
        elif node.tag.startswith("{http://www.w3.org/1999/xhtml}"):
            node.tag = node.tag.split("}", 1)[1]
        node.attrib = {
            key.replace(namespace, "data-d-"): value
            for key, value in node.attrib.items()
        }
    return (
        {
            "id": entry_id,
            "source": source,
            "source_id": source_id,
            "headword": headword,
            "search_key": normalized(headword),
            "audio_id": content_id("headword", source, source_id, headword),
            "html": ET.tostring(root, encoding="unicode", method="html"),
            "pronunciations": json.dumps(pronunciations, ensure_ascii=False),
        },
        examples,
        aliases,
    )


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
                headword TEXT, search_key TEXT, audio_id TEXT, html TEXT, pronunciations TEXT);
            CREATE TABLE aliases (term TEXT, entry_id TEXT, PRIMARY KEY (term, entry_id));
            CREATE TABLE examples (id TEXT PRIMARY KEY, entry_id TEXT, sense_id TEXT,
                text TEXT, context TEXT, needs_review INTEGER);
            CREATE INDEX entries_reference ON entries(source, source_id);
            CREATE INDEX examples_entry ON examples(entry_id);
        """)
        for source, bundle in sorted(bundles.items()):
            resources = bundle / "Contents/Resources"
            db.execute(
                "INSERT INTO dictionaries VALUES (?, ?, ?)",
                (
                    source,
                    str(resources),
                    (resources / "DefaultStyle.css").read_text(),
                ),
            )
            count = 0
            for root in entries(resources / "Body.data"):
                parsed = parse_entry(source, root)
                if parsed is None:
                    continue
                entry, examples, aliases = parsed
                db.execute(
                    "INSERT INTO entries VALUES (:id,:source,:source_id,:headword,:search_key,:audio_id,:html,:pronunciations)",
                    entry,
                )
                db.executemany(
                    "INSERT OR IGNORE INTO examples VALUES (:id,:entry_id,:sense_id,:text,:context,:needs_review)",
                    examples,
                )
                db.executemany(
                    "INSERT INTO aliases VALUES (?, ?)",
                    ((term, entry["id"]) for term in aliases),
                )
                count += 1
            print(f"{source}: imported {count:,} English entries", flush=True)
    db.close()
    pending.replace(output / "dictionary.sqlite")


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


def main() -> None:
    """Run discovery, import, or audio-job export from the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("discover", "import"):
        sub = commands.add_parser(command)
        sub.add_argument(
            "--root",
            type=Path,
            action="append",
            help="Search root or .dictionary bundle; repeatable",
        )
        if command == "import":
            sub.add_argument("--output", type=Path, default=Path("build/Library"))
    sub = commands.add_parser("export")
    sub.add_argument("--library", type=Path, default=Path("build/Library"))
    sub.add_argument("--output", type=Path, required=True)
    sub.add_argument("--kind", choices=("examples", "headwords"), default="examples")
    sub.add_argument("--accent", choices=("us", "uk"), required=True)
    sub.add_argument(
        "--fallback", action="store_true", help="Use audio/fallback output paths"
    )
    args = parser.parse_args()
    if args.command == "export":
        print(
            f"Exported {export_audio(args.library, args.output, args.kind, args.accent, args.fallback):,} jobs to {args.output}"
        )
    else:
        bundles = discover(
            args.root
            or [
                Path(
                    "/System/Library/AssetsV2/com_apple_MobileAsset_DictionaryServices_dictionary3macOS"
                )
            ]
        )
        for name, path in sorted(bundles.items()):
            print(f"{name}: {path}")
        missing = {"WISDOM", "ODE"} - bundles.keys()
        if missing:
            parser.error(
                "Enable/download these dictionaries in Dictionary.app first: "
                + ", ".join(sorted(missing))
            )
        if args.command == "import":
            import_library(bundles, args.output)


if __name__ == "__main__":
    main()
