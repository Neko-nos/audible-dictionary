"""Regenerate failed ASR recordings with Kokoro on CUDA."""

import argparse
import json
from concurrent.futures import ProcessPoolExecutor
from multiprocessing import get_context
from pathlib import Path
from tempfile import TemporaryDirectory

import torch
from kokoro import KPipeline

from audibledict.asr.qwen import transcribe_shard
from audibledict.tts.audio import save_recording
from audibledict.tts.breeze.schedule import partition_jobs
from audibledict.tts.fallback.kokoro_speech import Kokoro, NoAudioError


def synthesize_shard(rank: int, records: list[dict]) -> list[dict]:
    """Replace one GPU's failed recordings using their original accent.

    Args:
        rank (int): Index within the visible CUDA devices.
        records (list[dict]): Failed ASR results with source and accent metadata.

    Returns:
        list[dict]: Records whose audio was regenerated and needs ASR validation.
    """
    speakers = {}
    generated = []
    for record in records:
        source, accent = record["source"], record["accent"]
        if accent not in speakers:
            speakers[accent] = Kokoro(source, accent, device=f"cuda:{rank}")
        destination = Path(record["output"])
        try:
            audio = speakers[accent].synthesize(record["text"])
        except NoAudioError as error:
            print(f"[GPU {rank}] {destination}: {error}", flush=True)
            continue
        save_recording(destination, audio)
        generated.append(record)
        print(f"[GPU {rank}] Saved {destination}", flush=True)
    return generated


def regenerate(report: Path, max_cer: float) -> int:
    """Regenerate rejected recordings once and refresh their ASR results.

    Args:
        report (Path): ASR JSONL report in the audio output directory.
        max_cer (float): Maximum normalized character error rate to accept.

    Returns:
        int: Number of recordings still failing after Kokoro generation.
    """
    with report.open(encoding="utf-8") as stream:
        scores = {item["output"]: item for item in map(json.loads, stream)}
    pending = []
    for result in scores.values():
        if result["passed"]:
            continue
        source, *accent, _ = (
            Path(result["output"]).resolve().relative_to(report.parent.resolve()).parts
        )
        pending.append(
            {
                **result,
                "source": source,
                "accent": accent[0]
                if accent
                else {"WISDOM": "us", "ODE": "uk"}[source],
            }
        )
    if not pending:
        return 0
    gpu_count = torch.cuda.device_count()
    context = get_context("spawn")
    tokenizers = {
        accent: KPipeline(lang_code=language, model=False)
        for accent, language in (("us", "a"), ("uk", "b"))
    }
    # Kokoro consumes phonemes, so balance work using its own English frontend.
    lengths = (
        sum(
            len(chunk.phonemes)
            for chunk in tokenizers[record["accent"]](record["text"])
        )
        for record in pending
    )
    shards = partition_jobs(pending, gpu_count, lengths)
    allocations = [(rank, shard) for rank, shard in enumerate(shards) if shard]
    print(f"Generating {len(pending):,} Kokoro recordings", flush=True)
    with ProcessPoolExecutor(max_workers=gpu_count, mp_context=context) as pool:
        generated_shards = list(
            pool.map(synthesize_shard, *zip(*allocations, strict=True))
        )
    generated = {record["output"] for shard in generated_shards for record in shard}
    for record in pending:
        if record["output"] not in generated:
            result = scores[record["output"]]
            result["attempt"] += 1
            result["generation_error"] = "Kokoro produced no audio chunks"
    # Do not score the previous recording as though Kokoro regenerated it.
    allocations = [
        (rank, shard) for rank, shard in enumerate(generated_shards) if shard
    ]
    # Fresh ASR processes can claim GPU memory after Kokoro workers exit.
    if allocations:
        with ProcessPoolExecutor(max_workers=gpu_count, mp_context=context) as pool:
            for results in pool.map(transcribe_shard, *zip(*allocations, strict=True)):
                for result in results:
                    previous = scores[result["output"]]
                    result["passed"] = (
                        result["cer"] <= max_cer and not result["truncated"]
                    )
                    result["attempt"] = previous["attempt"] + 1
                    result["tts_model"] = "hexgrad/Kokoro-82M"
                    scores[result["output"]] = result
    with TemporaryDirectory(dir=report.parent) as directory:
        updated = Path(directory) / report.name
        with updated.open("w", encoding="utf-8") as stream:
            for result in scores.values():
                stream.write(json.dumps(result, ensure_ascii=False) + "\n")
        updated.replace(report)
    return sum(not result["passed"] for result in scores.values())


def main() -> None:
    """Run the final Kokoro fallback for failed recordings in an ASR report."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "report", type=Path, help="ASR JSONL report in the audio directory"
    )
    parser.add_argument(
        "-c", "--max-cer", type=float, default=0.05, help="Maximum CER (default: 0.05)"
    )
    args = parser.parse_args()
    failed = regenerate(args.report, args.max_cer)
    print(
        f"Kokoro fallback complete: {failed:,} recordings remain failed; see {args.report}"
    )


if __name__ == "__main__":
    main()
