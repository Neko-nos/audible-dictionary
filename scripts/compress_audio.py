"""Compress an audio directory into small, independent ALAC/CAF ZIPs on Ubuntu."""

import argparse
from io import BytesIO
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile

import soundfile as sf


def compress_archive(source: Path, output: Path, part_size: int) -> None:
    """Create independent ALAC ZIPs directly from a recording directory.

    Args:
        source (Path): Directory containing 16-bit PCM CAF recordings.
        output (Path): New directory receiving ZIPs with recordings under audio/.
        part_size (int): Target bytes per ZIP, before its closing directory.
    """
    source = source.resolve()
    recordings = sorted(source.rglob("*.caf"))
    pending = iter(recordings)
    recording = next(pending, None)
    index = 0
    part = 0
    output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=output.parent) as directory:
        while recording is not None:
            part += 1
            encoded = Path(directory) / f"audio-{part:04d}.zip"
            # ALAC already compresses the audio; another compression pass saves little.
            with ZipFile(encoded, "w") as converted:
                while recording is not None:
                    name = Path("audio") / recording.relative_to(source)
                    audio, rate = sf.read(recording, dtype="int16")
                    buffer = BytesIO()
                    sf.write(buffer, audio, rate, format="CAF", subtype="ALAC_16")
                    converted.writestr(name.as_posix(), buffer.getvalue())
                    index += 1
                    # Keep long conversions observable without logging every recording.
                    if index % 1000 == 0:
                        print(
                            f"Processed {index:,}/{len(recordings):,} recordings",
                            flush=True,
                        )
                    recording = next(pending, None)
                    # Keep each recording whole so every ZIP works independently.
                    if converted.fp.tell() >= part_size:
                        break
            print(f"Created {encoded.name}", flush=True)
        Path(directory).replace(output)


def main() -> None:
    """Compress the audio directory selected on the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Source audio directory")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        required=True,
        help="New directory for ALAC ZIP parts",
    )
    parser.add_argument(
        "-s",
        "--part-size-mb",
        type=float,
        default=1000,
        help="Approximate size per ZIP in MB (default: 1000)",
    )
    args = parser.parse_args()
    compress_archive(args.directory, args.output, int(args.part_size_mb * 1_000_000))
    print(f"Created {args.output}")


if __name__ == "__main__":
    main()
