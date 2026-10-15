"""Check independent ZIP parts and conversion using synthetic recordings."""

import subprocess
import sys
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile

import numpy as np
import pytest
import soundfile as sf
from jaxtyping import Int

from scripts.extract_audio import extract_opus


@pytest.fixture(params=[360, 8952, 24000])
def recording_directory(
    tmp_path: Path, request: pytest.FixtureRequest
) -> tuple[Path, Int[np.ndarray, " samples"]]:
    """Create PCM recordings covering partial and complete codec frames.

    Args:
        tmp_path (Path): Directory for generated fixtures.
        request (pytest.FixtureRequest): Synthetic waveform length.

    Returns:
        tuple: Directory path and original 16-bit samples.
    """
    time = np.arange(request.param) / 24000
    samples = np.round(10000 * np.sin(2 * np.pi * 440 * time)).astype(np.int16)
    source = tmp_path / "recordings"
    for name in (
        "DUMMY_ONE/uk/placeholder.caf",
        "DUMMY_ONE/us/placeholder.caf",
        "DUMMY_TWO/example.caf",
    ):
        recording = source / name
        recording.parent.mkdir(parents=True, exist_ok=True)
        sf.write(recording, samples, 24000, subtype="PCM_16")
    return source, samples


@pytest.mark.parametrize(("part_size_mb", "expected_parts"), [(1, 1), (0.000001, 3)])
def test_alac_archives(
    tmp_path: Path,
    recording_directory: tuple[Path, Int[np.ndarray, " samples"]],
    part_size_mb: float,
    expected_parts: int,
) -> None:
    """Preserve every recording exactly once across independently readable ZIPs.

    Args:
        tmp_path (Path): Directory for the compressed archives.
        recording_directory (tuple): Dummy recordings and their original samples.
        part_size_mb (float): Part size, including a limit smaller than one recording.
        expected_parts (int): Expected number of independently readable archives.
    """
    source, samples = recording_directory
    output = tmp_path / "parts"
    subprocess.run(
        [
            "uv",
            "run",
            "--no-sync",
            str(Path(__file__).resolve().parents[1] / "scripts/compress_audio.py"),
            str(source),
            "-o",
            str(output),
            "-s",
            str(part_size_mb),
        ],
        check=True,
    )
    parts = sorted(output.glob("*.zip"))
    assert len(parts) == expected_parts
    names = []
    for part in parts:
        with ZipFile(part) as converted:
            names.extend(converted.namelist())
            assert converted.testzip() is None
            for member in converted.infolist():
                recording = BytesIO(converted.read(member))
                info = sf.info(recording)
                assert (info.format, info.subtype, info.channels) == (
                    "CAF",
                    "ALAC_16",
                    1,
                )
                recording.seek(0)
                decoded, rate = sf.read(recording, dtype="int16")
                assert rate == 24000
                np.testing.assert_array_equal(decoded, samples)
    assert names == [
        "audio/DUMMY_ONE/uk/placeholder.caf",
        "audio/DUMMY_ONE/us/placeholder.caf",
        "audio/DUMMY_TWO/example.caf",
    ]


@pytest.mark.skipif(sys.platform != "darwin", reason="Requires Apple's afconvert")
def test_opus_extraction(
    tmp_path: Path, recording_directory: tuple[Path, Int[np.ndarray, " samples"]]
) -> None:
    """Use Apple's encoder and decoder to verify Opus output and temporary cleanup.

    Args:
        tmp_path (Path): Directory for compressed and extracted dummy recordings.
        recording_directory (tuple): Dummy recordings and their original samples.
    """
    source, samples = recording_directory
    alac = tmp_path / "parts"
    subprocess.run(
        [
            "uv",
            "run",
            "--no-sync",
            str(Path(__file__).resolve().parents[1] / "scripts/compress_audio.py"),
            str(source),
            "-o",
            str(alac),
            "-s",
            "0.000001",
        ],
        check=True,
    )
    output = tmp_path / "build/audio"
    output.mkdir(parents=True)
    for part in sorted(alac.glob("*.zip")):
        extract_opus(part, output)
    assert set(output.iterdir()) == {output / "DUMMY_ONE", output / "DUMMY_TWO"}
    recordings = sorted(output.rglob("*.caf"))
    assert len(recordings) == 3
    for index, recording in enumerate(recordings):
        assert recording.read_bytes()[28:32] == b"opus"
        wave = tmp_path / f"decoded-{index}.wav"
        subprocess.run(
            [
                "/usr/bin/afconvert",
                "-f",
                "WAVE",
                "-d",
                "LEI16",
                str(recording),
                str(wave),
            ],
            check=True,
        )
        decoded, rate = sf.read(wave, dtype="int16")
        assert rate == 24000
        assert len(decoded) == len(samples)
        assert np.corrcoef(decoded, samples)[0, 1] > 0.95


@pytest.mark.skipif(sys.platform != "darwin", reason="Requires Apple's afconvert")
def test_failed_conversion_keeps_zip(tmp_path: Path) -> None:
    """Keep the input archive when Apple's encoder rejects a corrupt recording.

    Args:
        tmp_path (Path): Directory for an intentionally invalid dummy recording.
    """
    source = tmp_path / "invalid.zip"
    with ZipFile(source, "w") as archive:
        archive.writestr("audio/DUMMY/invalid.caf", b"invalid dummy audio")
    original = source.read_bytes()
    output = tmp_path / "extracted"
    output.mkdir()
    with pytest.raises(subprocess.CalledProcessError):
        extract_opus(source, output)
    assert source.read_bytes() == original
    assert list(output.iterdir()) == []
