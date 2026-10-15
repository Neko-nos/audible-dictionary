"""Write generated speech as complete CAF recordings."""

from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
import soundfile as sf
from jaxtyping import Float


def save_recording(destination: Path, audio: Float[np.ndarray, " samples"]) -> None:
    """Write a complete CAF atomically so interrupted recordings can be resumed.

    Args:
        destination (Path): Final recording path.
        audio (Float[np.ndarray, " samples"]): Mono waveform at 24 kHz.
    """
    destination.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=destination.parent) as directory:
        encoded = Path(directory) / "speech.caf"
        sf.write(encoded, audio, 24000, subtype="PCM_16")
        encoded.replace(destination)
