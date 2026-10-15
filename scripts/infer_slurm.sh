#!/usr/bin/env bash
#SBATCH --job-name=audibledict_synth
#SBATCH --output=logs/%j/job.out
#SBATCH --error=logs/%j/job.err
#SBATCH --partition=dgx-a100-80g
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --gres=gpu:nvidia_a100-sxm4-80gb:2
#SBATCH --time=2-00:00:00

set -euo pipefail

cd "$SLURM_SUBMIT_DIR"

exec uv run audibledict/tts/breeze/cli.py "$@"
