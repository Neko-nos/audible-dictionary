"""Import installed WISDOM and ODE dictionaries and export English audio jobs."""

import argparse
from pathlib import Path

from audibledict.dictionaries.bundles import discover
from audibledict.dictionaries.export import export_audio
from audibledict.dictionaries.library import import_library


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
    sub.add_argument(
        "-a",
        "--accent",
        choices=("us", "uk"),
        help="Speech accent; defaults to both for headwords, US for WISDOM examples, UK for ODE examples",
    )
    args = parser.parse_args()
    if args.command == "export":
        print(
            f"Exported {export_audio(args.library, args.output, args.kind, args.accent):,} jobs to {args.output}"
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
