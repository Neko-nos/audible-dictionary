"""Generate independent recordings with Elliot (US) and Alistair (UK)."""

import json
from importlib.resources import files
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.request import Request, urlopen
from uuid import uuid4

import numpy as np
import soundfile as sf
from jaxtyping import Float
from transformers import GemmaTokenizer
from vllm.sampling_params import RequestOutputKind
from vllm_omni import AsyncOmni
from vllm_omni.model_executor.models.breeze_tts_2.prompt import build_breeze_prompt


class Breeze:
    """Keep one vLLM-Omni engine loaded for an independent GPU worker."""

    def __init__(self, rank: int, model: str, max_num_seqs: int) -> None:
        """Load the official checkpoint and reference speakers with vLLM-Omni.

        Args:
            rank (int): Index within the visible CUDA devices.
            model (str): Official Breeze checkpoint in the Hugging Face cache.
            max_num_seqs (int): Maximum active sequences in each vLLM stage.
        """
        self.speakers = json.loads(
            Path(__file__).with_name("speakers.json").read_text(encoding="utf-8")
        )
        references = Path(".cache/breeze/references")
        references.mkdir(parents=True, exist_ok=True)
        for speaker in self.speakers.values():
            audio = references / speaker["audio"]
            if not audio.exists():
                request = Request(
                    speaker["source"], headers={"User-Agent": "audible-dictionary"}
                )
                # Interrupted downloads must not be reused as complete references.
                with TemporaryDirectory(dir=references) as directory:
                    downloaded = Path(directory) / audio.name
                    with urlopen(request, timeout=30) as response:
                        downloaded.write_bytes(response.read())
                    downloaded.replace(audio)
        self.references = {
            accent: sf.read(references / speaker["audio"], dtype="float32")
            for accent, speaker in self.speakers.items()
        }
        self.tokenizer = GemmaTokenizer.from_pretrained(model)
        # ref: https://github.com/vllm-project/vllm-omni/blob/v0.30.0/vllm_omni/deploy/breeze_tts_2_throughput.yaml#L39
        self.engine = AsyncOmni(
            model=model,
            deploy_config=str(
                files("vllm_omni") / "deploy/breeze_tts_2_throughput.yaml"
            ),
            stage_0_devices=str(rank),
            stage_1_devices=str(rank),
            stage_0_max_num_seqs=max_num_seqs,
            stage_1_max_num_seqs=max_num_seqs,
        )
        # AsyncOmni streams audio deltas by default; CAF files need complete waveforms.
        self.sampling_params = [
            params.clone() for params in self.engine.default_sampling_params_list
        ]
        for params in self.sampling_params:
            params.output_kind = RequestOutputKind.FINAL_ONLY

    async def synthesize(self, record: dict[str, str]) -> Float[np.ndarray, " samples"]:
        """Generate one complete recording.

        Args:
            record (dict[str, str]): Export record with text, accent, and output path.

        Returns:
            Float[np.ndarray, " samples"]: Complete mono waveform.
        """
        # ref: https://github.com/vllm-project/vllm-omni/blob/v0.30.0/vllm_omni/model_executor/models/breeze_tts_2/prompt.py#L23
        prompt = build_breeze_prompt(
            self.tokenizer,
            record["text"],
            ref_audio=self.references[record["accent"]],
            ref_text=self.speakers[record["accent"]]["text"],
        )
        # The shared-memory connector embeds request IDs in filenames.
        request_id = uuid4().hex
        sampling_params = [params.clone() for params in self.sampling_params]
        # Reusing the profile's fixed seed would reproduce rejected recordings.
        sampling_params[0].seed = int(request_id[:8], 16)
        async for output in self.engine.generate(
            prompt,
            request_id=request_id,
            sampling_params_list=sampling_params,
        ):
            audio = output.outputs[0].multimodal_output["audio"]
        return audio.reshape(-1).float().cpu().numpy()
