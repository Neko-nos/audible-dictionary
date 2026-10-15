"""Validate complete recordings with Qwen3-ASR through vLLM."""

import os

import soundfile as sf
from transformers import AutoProcessor
from vllm import LLM, SamplingParams

from audibledict.asr.metrics import character_error_rates


def transcribe_shard(
    rank: int, records: list[dict[str, str]]
) -> list[dict[str, str | float | bool]]:
    """Transcribe one allocation on a single GPU and score each recording.

    Args:
        rank (int): Index within the visible CUDA devices.
        records (list[dict[str, str]]): Records with reference text and audio paths.

    Returns:
        list[dict[str, str | float | bool]]: Audio paths, transcripts, CER values,
            and whether ASR stopped at its output token limit.
    """
    # Each worker owns one visible GPU, including when Slurm supplies device UUIDs.
    devices = os.environ.get("CUDA_VISIBLE_DEVICES")
    os.environ["CUDA_VISIBLE_DEVICES"] = (
        devices.split(",")[rank] if devices else str(rank)
    )
    model = "Qwen/Qwen3-ASR-1.7B-hf"
    processor = AutoProcessor.from_pretrained(model)
    engine = LLM(model=model)
    # No reference text is supplied to ASR: it must recognize the audio independently.
    prompt = processor.apply_chat_template(
        [{"role": "user", "content": [{"type": "audio"}]}],
        tokenize=False,
        add_generation_prompt=True,
    )
    # Use Qwen's greedy decoding with enough output space for dictionary sentences.
    # ref: https://github.com/QwenLM/Qwen3-ASR/blob/main/README.md#L617
    sampling_params = SamplingParams(temperature=0, max_tokens=512)
    outputs = engine.generate(
        [
            {
                "prompt": prompt,
                "multi_modal_data": {
                    "audio": sf.read(record["output"], dtype="float32")
                },
            }
            for record in records
        ],
        sampling_params,
    )
    transcripts = processor.extract_transcription(
        [output.outputs[0].text for output in outputs]
    )
    scores = character_error_rates([record["text"] for record in records], transcripts)
    return [
        {
            "output": record["output"],
            "text": record["text"],
            "transcript": transcript,
            "cer": score,
            "truncated": output.outputs[0].finish_reason == "length",
        }
        for record, output, transcript, score in zip(
            records, outputs, transcripts, scores, strict=True
        )
    ]
