"""Generate primary CAF recordings from exported dictionary JSONL on CUDA."""

import argparse
import asyncio
import json
from concurrent.futures import ProcessPoolExecutor
from contextlib import closing
from itertools import batched, repeat
from multiprocessing import get_context
from pathlib import Path
from time import perf_counter

import torch
from huggingface_hub import snapshot_download
from transformers import GemmaTokenizer

from audibledict.asr.qwen import transcribe_shard
from audibledict.tts.audio import save_recording
from audibledict.tts.breeze.schedule import partition_jobs, resume_jobs
from audibledict.tts.breeze.speech import Breeze


def synthesize_shard(
    rank: int,
    records: list[dict[str, str]],
    model: str,
    max_num_seqs: int,
) -> None:
    """Process one GPU's allocation independently.

    Args:
        rank (int): Index within the visible CUDA devices.
        records (list[dict[str, str]]): Allocated records with output paths.
        model (str): Official Breeze checkpoint in the Hugging Face cache.
        max_num_seqs (int): Maximum active sequences in each vLLM stage.
    """

    async def run() -> None:
        """Continuously refill this GPU's requests as recordings finish."""
        breeze = Breeze(rank, model, max_num_seqs)
        pending = iter(records)

        async def consume() -> None:
            """Consume the shared iterator without blocking other requests on file I/O."""
            for job in pending:
                audio = await breeze.synthesize(job)
                await asyncio.to_thread(save_recording, Path(job["output"]), audio)
                print(f"[GPU {rank}] Saved {job['output']}", flush=True)

        with closing(breeze.engine):
            started = perf_counter()
            async with asyncio.TaskGroup() as group:
                # Bound queueing so requests reach the decoder before its input deadline.
                for _ in range(min(len(records), 2 * max_num_seqs)):
                    group.create_task(consume())
            print(
                f"[GPU {rank}] Generated {len(records)} recordings; "
                f"elapsed {perf_counter() - started:.2f}s",
                flush=True,
            )

    asyncio.run(run())


def main() -> None:
    """Generate recordings, then repeat ASR validation and regeneration of failures."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jobs", type=Path, help="Exported JSONL file")
    parser.add_argument(
        "-k",
        "--kind",
        choices=("examples", "headwords"),
        default="examples",
        help="Export kind",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path("build/audio"),
        help="Audio output directory (default: build/audio, relative to the working directory)",
    )
    parser.add_argument(
        "-s",
        "--max-num-seqs",
        type=int,
        # Match the bundled throughput profile to avoid excessive connector wait times.
        default=32,
        help="Maximum active TTS sequences per GPU stage (default: 32)",
    )
    parser.add_argument(
        "-a",
        "--max-attempts",
        type=int,
        default=5,
        help="Maximum generation and ASR validation rounds (default: 5)",
    )
    parser.add_argument(
        "-c",
        "--max-cer",
        type=float,
        default=0.05,
        help="Maximum normalized character error rate (default: 0.05)",
    )
    args = parser.parse_args()

    records = []
    with args.jobs.open(encoding="utf-8") as stream:
        for line in stream:
            job = json.loads(line)
            directory = args.output / job["source"]
            if args.kind == "headwords":
                directory /= job["accent"]
            destination = directory / f"{job['id']}.caf"
            records.append({**job, "output": str(destination)})
    if records:
        model = snapshot_download("BreezeBlue/Breeze-TTS-2")
        # Load the checkpoint's tokenizer without parsing its custom model config.
        # ref: https://huggingface.co/BreezeBlue/Breeze-TTS-2/blob/main/tokenizer_config.json
        tokenizer = GemmaTokenizer.from_pretrained(model)
        gpu_count = torch.cuda.device_count()
        # Fresh processes avoid inheriting the parent's tokenizer threads and CUDA state.
        context = get_context("spawn")
        pending = records
        scores = {}
        report = args.output / f"asr-{args.kind}.jsonl"
        for attempt in range(1, args.max_attempts + 1):
            # Bound temporary token arrays while using the tokenizer's native batch API.
            lengths = (
                length
                for batch in batched(pending, 4096)
                for length in tokenizer(
                    [record["text"] for record in batch],
                    return_length=True,
                    return_attention_mask=False,
                )["length"]
            )
            shards = partition_jobs(pending, gpu_count, lengths)
            if attempt == 1:
                # Allocate the full export before resuming to preserve each GPU's job order.
                shards = [resume_jobs(shard) for shard in shards]
            allocations = [(rank, shard) for rank, shard in enumerate(shards) if shard]
            print(
                f"Round {attempt}/{args.max_attempts}: generating "
                f"{sum(len(shard) for _, shard in allocations):,} recordings",
                flush=True,
            )
            with ProcessPoolExecutor(max_workers=gpu_count, mp_context=context) as pool:
                list(
                    pool.map(
                        synthesize_shard,
                        (rank for rank, _ in allocations),
                        (shard for _, shard in allocations),
                        repeat(model),
                        repeat(args.max_num_seqs),
                    )
                )
            # Exiting the TTS pool releases all GPU memory before ASR starts.
            shards = [pending[rank::gpu_count] for rank in range(gpu_count)]
            allocations = [(rank, shard) for rank, shard in enumerate(shards) if shard]
            with ProcessPoolExecutor(max_workers=gpu_count, mp_context=context) as pool:
                for results in pool.map(
                    transcribe_shard,
                    (rank for rank, _ in allocations),
                    (shard for _, shard in allocations),
                ):
                    for result in results:
                        result["passed"] = (
                            result["cer"] <= args.max_cer and not result["truncated"]
                        )
                        result["attempt"] = attempt
                        scores[result["output"]] = result
            with report.open("w", encoding="utf-8") as stream:
                for result in scores.values():
                    stream.write(json.dumps(result, ensure_ascii=False) + "\n")
            pending = [job for job in pending if not scores[job["output"]]["passed"]]
            print(
                f"Round {attempt}: {len(pending):,} recordings failed ASR", flush=True
            )
            if not pending:
                break
        if pending:
            raise SystemExit(
                f"{len(pending):,} recordings failed after {args.max_attempts} rounds; "
                f"see {report}"
            )
    print(f"Validated {len(records):,} recordings in {args.output}")


if __name__ == "__main__":
    main()
