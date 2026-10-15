"""Check CER with invented transcripts."""

import pytest

from audibledict.asr.metrics import character_error_rates


@pytest.mark.parametrize(
    ("reference", "transcript", "expected"),
    [
        ("Moon-light!", "MOON LIGHT", 0.0),
        ("ＡＢＣ", "abc", 0.0),
        ("abcd", "abxd", 0.25),
        ("abcd", "abc", 0.25),
        ("abcd", "abcde", 0.25),
        ("café", "cafe", 0.0),
        ("I paid twenty dollars.", "I paid $20", 0.0),
        ("I can't see its colour.", "I can not see its color", 0.0),
        ("The Q Z V robot sleeps.", "The QZV robot sleeps.", 0.0),
        ("The teapot has wi-fi.", "The teapot has wifi.", 0.0),
        (
            "Katherine pilots the paper rocket.",
            "Catherine pilots the paper rocket.",
            0.0,
        ),
        ("", "", 0.0),
        (".", "", 0.0),
        (".", "moon", 4.0),
    ],
)
def test_character_error_rate(reference: str, transcript: str, expected: float) -> None:
    """Score edits and typography, including punctuation-only references.

    Args:
        reference (str): Invented intended speech.
        transcript (str): Invented ASR output.
        expected (float): Expected normalized CER.
    """
    assert character_error_rates([reference], [transcript]) == pytest.approx([expected])
