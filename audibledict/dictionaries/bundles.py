"""Discover installed dictionary bundles and decode their records."""

import plistlib
import struct
import xml.etree.ElementTree as ET
import zlib
from collections.abc import Iterator
from pathlib import Path


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
