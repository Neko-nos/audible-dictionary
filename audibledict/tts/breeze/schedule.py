"""Balance independent synthesis jobs across GPU workers."""

from collections.abc import Iterable
from pathlib import Path


def resume_jobs(records: list[dict[str, str]]) -> list[dict[str, str]]:
    """Resume an LPT allocation from its last consecutively completed job.

    Args:
        records (list[dict[str, str]]): One GPU's allocation with output paths.

    Returns:
        list[dict[str, str]]: Last completed job and the rest of the allocation.
    """
    # Later jobs can finish first; only a consecutive prefix establishes progress.
    for index, record in enumerate(records):
        if not Path(record["output"]).is_file():
            # Replay the boundary job because its existing audio may be invalid.
            return records[max(0, index - 1) :]
    return records[-1:]


def partition_jobs(
    records: list[dict[str, str]], workers: int, lengths: Iterable[int]
) -> list[list[dict[str, str]]]:
    """Assign jobs with the most tokens first to the least-loaded worker.

    Args:
        records (list[dict[str, str]]): Export records with output paths.
        workers (int): Number of GPU workers.
        lengths (Iterable[int]): Model input lengths in the same order as records.

    Returns:
        list[list[dict[str, str]]]: Disjoint shards in descending token-count order.
    """
    shards = [[] for _ in range(workers)]
    loads = [0] * workers
    for tokens, record in sorted(
        zip(lengths, records, strict=True), key=lambda job: job[0], reverse=True
    ):
        worker = loads.index(min(loads))
        shards[worker].append(record)
        loads[worker] += tokens
    return shards
