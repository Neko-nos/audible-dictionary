"""Generate English fallback speech with official Kokoro."""

import argparse
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory

import numpy as np
import soundfile as sf
import torch
from jaxtyping import Float
from kokoro import KPipeline


class NoAudioError(ValueError):
    """Kokoro produced no audio for the requested text."""


class Kokoro:
    """Run full-precision Kokoro inference on a PyTorch device."""

    def __init__(
        self, source: str, accent: str | None = None, *, device: str = "mps"
    ) -> None:
        """Initialize the official English speech pipeline.

        Args:
            source (str): Dictionary supplying the text, WISDOM or ODE.
            accent (str | None): Headword accent, us or uk; examples use the
                dictionary's accent when omitted.
            device (str): PyTorch device for inference.

        Raises:
            RuntimeError: The requested device is unavailable.
        """
        accent = accent or {"WISDOM": "us", "ODE": "uk"}[source]
        lang_code, self.voice = {
            # ref: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md#american-english
            "us": ("a", "af_heart"),
            # ref: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md#british-english
            "uk": ("b", "bf_emma"),
        }[accent]
        self.pipeline = KPipeline(lang_code=lang_code, device=device)

    def synthesize(self, text: str) -> Float[np.ndarray, " samples"]:
        """Synthesize the requested text, joining any model-sized chunks.

        Args:
            text (str): English headword or sentence to speak.

        Returns:
            Float[np.ndarray, " samples"]: Mono waveform at the model's sample rate.

        Raises:
            NoAudioError: The pipeline yielded no audio chunks.
        """
        chunks = [result.audio for result in self.pipeline(text, voice=self.voice)]
        if not chunks:
            raise NoAudioError("Kokoro produced no audio chunks")
        audio: Float[torch.Tensor, " samples"] = torch.cat(chunks)
        return audio.numpy()

    def write(self, text: str, output: Path) -> None:
        """Publish a complete Opus recording only after synthesis succeeds.

        Args:
            text (str): English headword or sentence to speak.
            output (Path): Destination CAF audio file.

        Raises:
            subprocess.CalledProcessError: macOS could not encode the recording.
        """
        audio = self.synthesize(text)
        output.parent.mkdir(parents=True, exist_ok=True)
        # Keep incomplete recordings out of the playback cache, including on cancellation.
        with TemporaryDirectory(prefix="kokoro-", dir=output.parent) as directory:
            wave = Path(directory) / "speech.wav"
            encoded = Path(directory) / "speech.caf"
            sf.write(wave, audio, 24000, subtype="FLOAT")
            subprocess.run(
                [
                    "/usr/bin/afconvert",
                    "-f",
                    "caff",
                    "-d",
                    "opus",
                    "-b",
                    "32000",
                    str(wave),
                    str(encoded),
                ],
                check=True,
            )
            encoded.replace(output)


def main() -> None:
    """Generate fallback speech for one requested headword or sentence."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--accent", choices=("us", "uk"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    Kokoro(args.source, args.accent).write(sys.stdin.read(), args.output)


if __name__ == "__main__":
    main()
