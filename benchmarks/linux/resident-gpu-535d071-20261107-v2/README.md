# Corrected one-L40S resident pilot candidate

This version fixes the one-GPU allocation check found in failed pilot
`1607281`. It accepts exactly one Slurm GPU ID, one CUDA-visible ID, and one
matching UUID in the visibility-filtered `nvidia-smi` inventory. It still
rejects an unfiltered inventory, missing UUID, or multiple allocated devices.
The launcher now records the observed allocation fields before validation,
so another identity failure is diagnosable without starting a GPU child.

Only `gpu_case_runner.py` and the versioned Slurm path/name differ from the
preserved pilot scripts. The case remains resident COIL20 2D UMAP with one
L40S and immutable package commit `535d071`. The large image is checked only
inside the compute allocation. No file-backed or SSD-streaming science is
permitted on UCT HPC.

Six local allocation mapping tests, Python syntax checks, `bash -n`, and
`git diff --check` passed. This is a staged candidate, **not a submitted or
device-qualified result**. On its terminal run, independently inspect the
allocated UUID, backend, finite output, scheduler result, owned descendants,
and GPU-context cleanup before any broader GPU campaign.
