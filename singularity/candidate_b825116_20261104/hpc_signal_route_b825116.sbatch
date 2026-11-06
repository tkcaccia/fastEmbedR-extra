#!/bin/bash
#SBATCH --job-name=fastembedr-signal-b825116
#SBATCH --partition=ada
#SBATCH --cpus-per-task=1
#SBATCH --mem=1G
#SBATCH --time=00:02:00
#SBATCH --signal=B:USR1@60
#SBATCH --output=/scratch/firenze/NN/singularity/candidate_b825116_20261104/signal-%j.out
#SBATCH --error=/scratch/firenze/NN/singularity/candidate_b825116_20261104/signal-%j.err
set -Eeuo pipefail
exec python3 /scratch/firenze/NN/singularity/candidate_b825116_20261104/hpc_signal_route_b825116.py
