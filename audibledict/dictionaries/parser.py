"""Extract contextual English entries and examples from dictionary markup."""

import hashlib
import re
import unicodedata
import xml.etree.ElementTree as ET

JAPANESE = re.compile(r"[\u3040-\u30ff\u3400-\u9fff\uff66-\uff9f]")
EDITORIAL = re.compile(r"[\[\]/≒…〜～]|\.{3}|_{2,}")
WHITESPACE = re.compile(r"\s+")


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


def typeset_spelling(node: ET.Element, headword: str) -> str:
    """Recover a searchable spelling from a WISDOM derivative or compound.

    Args:
        node (ET.Element): Word element, including stress markup.
        headword (str): Word substituted for the dictionary's repetition mark.

    Returns:
        str: Spelling without pronunciation, stress, or syllable separators.
    """
    text = (node.text or "") + "".join(
        ("" if "pr" in child.attrib.get("class", "").split() else plain_text(child))
        + (child.tail or "")
        for child in node
    )
    text = unicodedata.normalize("NFKD", text)
    text = "".join(char for char in text if not unicodedata.combining(char))
    text = text.translate(str.maketrans("", "", "・·ˈˌ"))
    for mark in ("~", "〜"):
        text = text.replace(mark, headword)
    return normalized(text)


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
    aliases = {normalized(headword)}
    for node in root.iter():
        classes = node.attrib.get("class", "").split()
        if set(classes) & {"hw", "hv", "subhw", "l", "f", "frm", "drv", "cw"}:
            alias = (
                typeset_spelling(node, headword)
                if set(classes) & {"drv", "cw"}
                else normalized(node.attrib.get("normalized", plain_text(node).strip()))
            )
            if alias and not JAPANESE.search(alias):
                aliases.add(alias)
                node.set("data-search-term", alias)
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
        audio_id = content_id("example", source, source_id, sense_id, text)
        node.set("data-audio-id", audio_id)
        examples.append(
            {
                "id": audio_id,
                "entry_id": entry_id,
                "text": text,
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
        },
        examples,
        aliases,
    )
