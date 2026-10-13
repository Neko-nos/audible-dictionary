"""CUDA integration coverage with invented text and synthetic recordings.

Install the tts extra and set KOKORO_GPU_TESTS=1 to run.
"""

import json
import os
import subprocess
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf
import torch


@pytest.mark.skipif(
    os.environ.get("KOKORO_GPU_TESTS") != "1" or not torch.cuda.is_available(),
    reason="Requires the official Kokoro and Qwen checkpoints on CUDA",
)
def test_regenerate_failed_recordings(tmp_path: Path) -> None:
    """Repair failed recordings and retain failures when Kokoro produces no audio.

    Args:
        tmp_path (Path): Directory for invented reports and generated audio.
    """
    records = []
    for relative, text, passed in [
        ("WISDOM/accepted.caf", "The velvet moon smiles.", True),
        ("WISDOM/dummy.caf", "A small red kite flies above the garden.", False),
        ("ODE/dummy.caf", "The little blue boat floats on the quiet lake.", False),
        ("WISDOM/us/dummy.caf", "teapot", False),
        ("ODE/uk/dummy.caf", "sunshine", False),
        # Kokoro's pronunciation markup makes the spoken word differ from the reference.
        ("ODE/asr-failure.caf", "The [teapot](/kˈæt/) naps.", False),
        ("WISDOM/us/no-audio.caf", " \t ", False),
    ]:
        output = tmp_path / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        sf.write(output, np.zeros(2400), 24000, subtype="PCM_16")
        records.append(
            {
                "output": str(output),
                "text": text,
                "transcript": text if passed else "",
                "cer": 0.0 if passed else 1.0,
                "truncated": False,
                "passed": passed,
                "attempt": 1,
            }
        )
    report = tmp_path / "asr-dummy.jsonl"
    report.write_text("".join(json.dumps(record) + "\n" for record in records))
    accepted = tmp_path / "WISDOM/accepted.caf"
    original = accepted.read_bytes(), accepted.stat().st_mtime_ns
    unspoken = tmp_path / "WISDOM/us/no-audio.caf"
    unspoken_original = unspoken.read_bytes(), unspoken.stat().st_mtime_ns
    command = [
        "uv",
        "run",
        "--no-sync",
        "audibledict/tts/fallback/regenerate.py",
        str(report),
    ]
    subprocess.run(command, check=True)
    results = list(map(json.loads, report.read_text().splitlines()))
    assert results[0] == records[0]
    assert (accepted.read_bytes(), accepted.stat().st_mtime_ns) == original
    for result in results[1:-2]:
        assert result["passed"]
        assert result["cer"] <= 0.05
        assert not result["truncated"]
        assert result["tts_model"] == "hexgrad/Kokoro-82M"
        assert result["attempt"] == 2
        info = sf.info(result["output"])
        assert (info.format, info.subtype, info.samplerate, info.channels) == (
            "CAF",
            "PCM_16",
            24000,
            1,
        )
        samples, _ = sf.read(result["output"])
        assert samples.size > 2400
        assert np.isfinite(samples).all()
        assert np.sqrt(np.mean(samples**2)) > 0.001
    assert not results[-2]["passed"]
    assert results[-2]["cer"] > 0.05
    assert results[-2]["tts_model"] == "hexgrad/Kokoro-82M"
    assert results[-2]["attempt"] == 2
    assert results[-1] == {
        **records[-1],
        "attempt": 2,
        "generation_error": "Kokoro produced no audio chunks",
    }
    assert (unspoken.read_bytes(), unspoken.stat().st_mtime_ns) == unspoken_original
