"""Score transcripts with the Open ASR Leaderboard's English normalization."""

from jiwer import cer

from audibledict.asr.open_asr_leaderboard.normalizer import EnglishTextNormalizer


def character_error_rates(references: list[str], transcripts: list[str]) -> list[float]:
    """Measure per-recording CER using Open ASR Leaderboard normalization.

    Args:
        references (list[str]): Intended speech for each recording.
        transcripts (list[str]): Recognized speech in the same order.

    Returns:
        list[float]: Character edits divided by reference length. For an empty
            normalized reference, each inserted character counts as one error.
    """
    # Use the benchmark linked by Qwen's model card so formatting and equivalent
    # spellings do not inflate CER, following its published normalization rules.
    # ref: https://huggingface.co/Qwen/Qwen3-ASR-1.7B-hf#evaluation
    normalizer = EnglishTextNormalizer()
    return [
        cer(normalizer(reference), normalizer(transcript))
        for reference, transcript in zip(references, transcripts, strict=True)
    ]
