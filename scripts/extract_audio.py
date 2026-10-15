"""Download ALAC ZIPs one at a time and convert them to Opus/CAF on macOS."""

import argparse
import shlex
import subprocess
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory
from zipfile import ZipFile


def extract_opus(source: Path, output: Path) -> None:
    """Convert one ZIP to 32 kbit/s Opus/CAF in the audio output directory.

    Args:
        source (Path): ZIP containing ALAC CAF recordings.
        output (Path): Existing audio directory receiving dictionary subfolders.

    Raises:
        subprocess.CalledProcessError: Apple's afconvert could not encode audio.
    """
    with ZipFile(source) as archive:
        members = archive.infolist()
        for index, member in enumerate(members, start=1):
            with TemporaryDirectory(dir=output) as directory:
                extracted = Path(archive.extract(member, Path(directory) / "input"))
                destination = output / extracted.relative_to(
                    Path(directory) / "input" / "audio"
                )
                encoded = Path(directory) / "speech.caf"
                subprocess.run(
                    [
                        "/usr/bin/afconvert",
                        "-f",
                        "caff",
                        "-d",
                        "opus",
                        "-b",
                        "32000",
                        str(extracted),
                        str(encoded),
                    ],
                    check=True,
                )
                destination.parent.mkdir(parents=True, exist_ok=True)
                encoded.replace(destination)
            if index % 1000 == 0:
                print(f"Processed {index:,}/{len(members):,} entries", flush=True)


def download_and_extract(source: str, output: Path) -> None:
    """Download and convert matching remote ZIPs without accumulating local copies.

    Args:
        source (str): SCP-style ZIP pattern, such as user@host:/path/*.zip.
        output (Path): Audio directory receiving dictionary subfolders.

    Raises:
        subprocess.CalledProcessError: SSH, SCP, or audio conversion failed.
    """
    host, pattern = source.split(":", 1)
    path = PurePosixPath(pattern)
    command = shlex.join(
        [
            "find",
            str(path.parent),
            "-maxdepth",
            "1",
            "-type",
            "f",
            "-name",
            path.name,
            "-print0",
        ]
    )
    result = subprocess.run(
        ["ssh", "--", host, command], check=True, capture_output=True, text=True
    )
    archives = sorted(result.stdout.split("\0")[:-1])
    output.mkdir(parents=True, exist_ok=True)
    print(f"Found {len(archives)} ZIPs", flush=True)
    for index, remote in enumerate(archives, start=1):
        print(f"Downloading {index}/{len(archives)}: {remote}", flush=True)
        # Server copies remain available; clean local downloads even if conversion fails.
        with TemporaryDirectory(dir=output) as directory:
            downloaded = Path(directory) / PurePosixPath(remote).name
            subprocess.run(
                ["scp", "--", f"{host}:{remote}", str(downloaded)], check=True
            )
            extract_opus(downloaded, output)
        print(f"Finished {index}/{len(archives)}; removed downloaded ZIP", flush=True)


def main() -> None:
    """Download and convert the remote recordings selected on the command line."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", help="SCP source pattern: [user@]host:/path/*.zip")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        required=True,
        help="Audio output directory, for example build/audio",
    )
    args = parser.parse_args()
    download_and_extract(args.source, args.output)
    print(f"Created {args.output}")


if __name__ == "__main__":
    main()
