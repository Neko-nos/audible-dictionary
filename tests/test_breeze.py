"""CUDA integration tests using invented dictionary exports.

Install the tts extra and set BREEZE_GPU_TESTS=1 on an idle CUDA machine.
"""

import json
import os
import subprocess
from pathlib import Path

import numpy as np
import pytest
import soundfile as sf
import torch
from transformers import GemmaTokenizer

from audibledict.tts.breeze.schedule import partition_jobs, resume_jobs


@pytest.mark.parametrize(
    ("completed", "pending"),
    [
        ([], [0, 1, 2, 3]),
        ([0, 1], [1, 2, 3]),
        ([2, 0], [0, 1, 2, 3]),
        ([1, 2, 3], [0, 1, 2, 3]),
        ([0, 1, 3], [1, 2, 3]),
        ([3, 1, 2, 0], [3]),
    ],
)
def test_resume_replays_boundary_job_and_remaining_allocation(
    tmp_path: Path, completed: list[int], pending: list[int]
) -> None:
    """Replay the LPT boundary and tail without skipping gaps in completion.

    Args:
        tmp_path (Path): Temporary recording directory.
        completed (list[int]): Job indices in completion order.
        pending (list[int]): Expected retry and unfinished job indices.
    """
    records = [{"output": str(tmp_path / f"dummy-{index}.caf")} for index in range(4)]
    for index in completed:
        recording = Path(records[index]["output"])
        recording.write_bytes(b"placeholder recording")
    assert resume_jobs(records) == [records[index] for index in pending]


def test_lpt_balances_work_and_assigns_every_record_once() -> None:
    """Balance an uneven invented workload without duplicating or losing jobs."""
    records = [
        {"id": str(index), "text": text}
        for index, text in enumerate(
            [
                "moon",
                "The blue kite floats.",
                "A tiny paper dragon sleeps beside the silver teapot.",
                "red blue green",
                "violet",
                "zzqx",
            ]
        )
    ]
    lengths = dict(
        zip((job["id"] for job in records), [2, 6, 11, 4, 2, 3], strict=True)
    )
    shards = partition_jobs(records, 2, lengths.values())
    assert [sum(lengths[job["id"]] for job in shard) for shard in shards] == [15, 13]
    assert sorted(job["id"] for shard in shards for job in shard) == [
        record["id"] for record in records
    ]


@pytest.mark.skipif(
    os.environ.get("BREEZE_GPU_TESTS") != "1",
    reason="Requires the real Breeze checkpoint and a CUDA GPU",
)
@pytest.mark.parametrize(
    ("kind", "workers"), [("examples", 1), ("headwords", 1), ("examples", 2)]
)
def test_recordings_resume(tmp_path: Path, kind: str, workers: int) -> None:
    """Generate both accents and verify CAF layout, resume, and regeneration.

    Args:
        tmp_path (Path): Temporary folder for invented exports and recordings.
        kind (str): Export kind to exercise through the real command-line pipeline.
        workers (int): Number of visible CUDA GPUs used by independent processes.
    """
    if torch.cuda.device_count() < workers:
        pytest.skip(f"Requires {workers} available CUDA GPUs")
    jobs = tmp_path / "jobs.jsonl"
    text = "The silver teapot hums softly." if kind == "examples" else "teapot"
    records = [
        {"text": text, "accent": "us", "id": "dummy", "source": "WISDOM"},
        {
            "text": (
                "A little paper dragon sleeps beside the silver teapot."
                if kind == "examples"
                else text
            ),
            "accent": "uk",
            "id": "dummy",
            "source": "ODE" if kind == "examples" else "WISDOM",
        },
        {"text": "dragon", "accent": "us", "id": "another", "source": "WISDOM"},
    ]
    # Exceed the request window so the GPU test exercises replenishment too.
    records.extend(
        {"text": text, "accent": "us", "id": f"dummy-{index}", "source": "WISDOM"}
        for index in range(6)
    )
    jobs.write_text("".join(json.dumps(record) + "\n" for record in records))
    output = tmp_path / "audio"
    command = [
        "uv",
        "run",
        "--no-sync",
        "audibledict/tts/breeze/cli.py",
        str(jobs),
        "--kind",
        kind,
        "--output",
        str(output),
        "--max-num-seqs",
        "2",
    ]
    devices = os.environ.get(
        "CUDA_VISIBLE_DEVICES", ",".join(str(rank) for rank in range(workers))
    ).split(",")
    env = {**os.environ, "CUDA_VISIBLE_DEVICES": ",".join(devices[:workers])}
    subprocess.run(command, check=True, env=env)
    if kind == "examples":
        paths = ["WISDOM/dummy.caf", "ODE/dummy.caf", "WISDOM/another.caf"]
        paths.extend(f"WISDOM/dummy-{index}.caf" for index in range(6))
    else:
        paths = ["WISDOM/us/dummy.caf", "WISDOM/uk/dummy.caf", "WISDOM/us/another.caf"]
        paths.extend(f"WISDOM/us/dummy-{index}.caf" for index in range(6))
    assert {str(path.relative_to(output)) for path in output.rglob("*.caf")} == set(
        paths
    )
    for path in paths:
        recording = output / path
        info = sf.info(recording)
        assert (info.format, info.subtype, info.samplerate, info.channels) == (
            "CAF",
            "PCM_16",
            24000,
            1,
        )
        samples, _ = sf.read(recording)
        # Even a short headword needs more than a tenth of a second of audio.
        assert samples.size > 2400
        assert np.isfinite(samples).all()
        assert np.sqrt(np.mean(samples**2)) > 0.001
    tokenizer = GemmaTokenizer.from_pretrained("BreezeBlue/Breeze-TTS-2")
    shards = partition_jobs(
        [
            {**record, "output": str(output / path)}
            for record, path in zip(records, paths, strict=True)
        ],
        workers,
        (len(tokenizer.encode(record["text"])) for record in records),
    )
    restarted = {shard[-1]["output"] for shard in shards}
    damaged = next(
        output / path
        for path in paths
        if str(output / path) not in restarted and path != paths[2]
    )
    # Replace a completed sentence with a different generated word to exercise ASR repair.
    damaged.write_bytes((output / paths[2]).read_bytes())
    modified = [(output / path).stat().st_mtime_ns for path in paths]
    subprocess.run(command, check=True, env=env)
    results = {
        result["output"]: result
        for result in map(
            json.loads, (output / f"asr-{kind}.jsonl").read_text().splitlines()
        )
    }
    assert all(result["passed"] for result in results.values())
    assert results[str(damaged)]["attempt"] > 1
    for path, timestamp in zip(paths, modified, strict=True):
        recording = output / path
        if str(recording) in restarted or recording == damaged:
            assert recording.stat().st_mtime_ns > timestamp
        else:
            assert recording.stat().st_mtime_ns == timestamp
