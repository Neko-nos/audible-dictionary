"""Exercise extraction and export with invented dictionary bundles only."""

import json
import plistlib
import sqlite3
import struct
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path

from audibledict.dictionaries.bundles import discover, entries
from audibledict.dictionaries.export import export_audio
from audibledict.dictionaries.library import import_library
from audibledict.dictionaries.parser import parse_entry


def dummy_entry(source_id: str = "WDEJ_dummy", title: str = "lumifern") -> bytes:
    """Construct invented nested markup with inline annotations and alternatives."""
    return f'''<d:entry xmlns:d="http://www.apple.com/DTDs/DictionaryService-1.0.rng"
        id="{source_id}" d:title="{title}">
        <span class="hw">{title}</span>
        <span class="semb" id="{source_id}_sense">
          <span d:def="1" class="trans">架空の光る植物</span>
          <span class="ex">The lumi<span class="italic">fern</span> glows softly.</span>
          <span class="ex">A [<span class="oup_label">｟架空｠ </span>the] lumifern glows.</span>
        </span>
        <span class="semb" id="{source_id}_other">
          <span class="df">An invented second sense.</span>
          <span class="ex">The lumifern glows softly.</span>
        </span>
        <span class="ex">日本語の説明</span>
        <span xmlns="http://www.w3.org/1999/xhtml" class="note">Dummy note</span>
    </d:entry>'''.encode()


def write_bundle(folder: Path, source: str, records: list[bytes]) -> Path:
    """Write actual zlib blocks and a plist using entirely invented entries."""
    bundle = folder / f"{source}.dictionary"
    resources = bundle / "Contents/Resources"
    resources.mkdir(parents=True)
    identifier = (
        "com.apple.dictionary.ja-en.WISDOM"
        if source == "WISDOM"
        else "com.apple.dictionary.ODE"
    )
    (bundle / "Contents/Info.plist").write_bytes(
        plistlib.dumps(
            {
                "CFBundleIdentifier": identifier,
            }
        )
    )
    (resources / "DefaultStyle.css").write_text(
        ".hw { font-weight: bold; } .semb { display: block; margin: 16px 0; }"
    )
    blocks = []
    for record in records:
        payload = struct.pack("<I", len(record)) + record
        compressed = zlib.compress(payload)
        block = struct.pack("<II", len(compressed) + 4, len(payload)) + compressed
        blocks.append(struct.pack("<I", len(block)) + block)
    header = bytearray(0x60)
    struct.pack_into("<I", header, 0x40, 0x20 + sum(map(len, blocks)))
    (resources / "Body.data").write_bytes(bytes(header) + b"".join(blocks))
    return bundle


def test_example_text_and_identity() -> None:
    entry, examples, aliases = parse_entry("WISDOM", ET.fromstring(dummy_entry()))
    assert examples[0]["text"] == "The lumifern glows softly."
    assert examples[1]["text"] == "A [the] lumifern glows."
    assert examples[1]["needs_review"]
    assert len(examples) == 3
    assert examples[0]["id"] != examples[2]["id"]
    assert 'data-audio-id="' + examples[0]["id"] + '"' in entry["html"]
    assert '<span class="note">Dummy note</span>' in entry["html"]
    assert "lumifern" in aliases


def test_binary_import_and_both_export_kinds(tmp_path: Path) -> None:
    bundles = tmp_path / "bundles"
    wisdom = write_bundle(
        bundles, "WISDOM", [dummy_entry(), dummy_entry("WDJE_dummy", "架空語")]
    )
    write_bundle(bundles, "ODE", [dummy_entry("m_dummy")])
    assert len(list(entries(wisdom / "Contents/Resources/Body.data"))) == 2
    library = tmp_path / "Library"
    import_library(discover([bundles]), library)
    with sqlite3.connect(library / "dictionary.sqlite") as db:
        assert db.execute("SELECT COUNT(*) FROM entries").fetchone()[0] == 2
        example_sources = dict(
            db.execute("""SELECT x.id, e.source FROM examples x
                          JOIN entries e ON e.id=x.entry_id""")
        )
        headword_sources = dict(db.execute("SELECT audio_id, source FROM entries"))
    export = tmp_path / "jobs.jsonl"
    assert export_audio(library, export, "examples") == 6
    jobs = [json.loads(line) for line in export.read_text().splitlines()]
    for job in jobs:
        source = example_sources[job["id"]]
        assert job["accent"] == {"WISDOM": "us", "ODE": "uk"}[source]
        assert job["source"] == source
    import_library(discover([bundles]), library)
    export_audio(library, export, "examples")
    reimported_jobs = [json.loads(line) for line in export.read_text().splitlines()]
    assert jobs == reimported_jobs
    for accent in ("us", "uk"):
        assert export_audio(library, export, "examples", accent) == 6
        accented_jobs = [json.loads(line) for line in export.read_text().splitlines()]
        assert accented_jobs == [{**job, "accent": accent} for job in jobs]
    assert export_audio(library, export, "headwords") == 4
    headwords = [json.loads(line) for line in export.read_text().splitlines()]
    assert {job["id"] for job in headwords[::2]} == {
        job["id"] for job in headwords[1::2]
    }
    for job, accent in zip(headwords, ["us", "uk"] * 2):
        source = headword_sources[job["id"]]
        assert job["accent"] == accent
        assert job["source"] == source
    assert export_audio(library, export, "headwords", "uk") == 2
    for line in export.read_text().splitlines():
        job = json.loads(line)
        source = headword_sources[job["id"]]
        assert job["accent"] == "uk"
        assert job["source"] == source
