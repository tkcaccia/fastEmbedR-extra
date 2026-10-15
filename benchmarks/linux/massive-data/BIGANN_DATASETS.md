# Turing-ANNS and DEEP downloads

This directory contains a resumable, standard-library-only downloader for
the Microsoft Turing-ANNS and Yandex DEEP base vectors listed by the
[Big ANN Benchmarks NeurIPS 2021 site](https://big-ann-benchmarks.com/neurips21.html).
The files are little-endian float32 `.fbin`: an eight-byte row/column header
followed by row-major values. A prefix is the **first** requested rows of
the official 1B file, not an independently sampled dataset. The downloader
updates the local header, writes a SHA-256 manifest, and leaves an incomplete
transfer as `.part` for the next run. Its `.part.meta.json` binds a partial
file to the source URL and ETag. A partial file created by older code without
this identity is rejected; inspect it rather than blindly resuming it. The
downloader rejects concurrent writes to the same dataset and row prefix. It
does not place vectors in Git.

| Dataset | Columns | Full base-file bytes | Terms |
| --- | ---: | ---: | --- |
| Turing-ANNS | 100 | 400,000,000,008 | [Research-only terms](https://big-ann-benchmarks.com/MSFT-Turing-ANNS-terms.txt) |
| Yandex DEEP | 96 | 384,000,000,008 | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

Read the Turing terms before downloading or using it. Do not redistribute
Turing vectors in the replication archive. The source URL, ETag, dimensions,
row count, elapsed download time, and local SHA-256 are recorded in each
`manifest.json`. The ETag is source identity, not a cryptographic checksum.
An existing completed file is rehashed and checked against its manifest.
If a run stopped after renaming the completed data but before writing the
manifest, the sidecar identity permits safe manifest recovery.

## Copy the scripts to Chiamaka HPC

Run this from the **Mac terminal**, not from the HPC shell. These are two
small files, not the data. Finish the `rsync` command and its password prompt
before logging in to the HPC:

```bash
SOURCE=/Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/massive-data
HOST=01481067@hex.uct.ac.za
test -f "$SOURCE/download_bigann_subset.py"
test -f "$SOURCE/slurm_download_bigann.sbatch"
rsync -av --rsync-path='mkdir -p /scratch/firenze/NN/benchmark_scripts/massive-data && rsync' \
  "$SOURCE/download_bigann_subset.py" \
  "$SOURCE/slurm_download_bigann.sbatch" \
  "$HOST:/scratch/firenze/NN/benchmark_scripts/massive-data/"
ssh "$HOST" 'ls -l /scratch/firenze/NN/benchmark_scripts/massive-data/download_bigann_subset.py /scratch/firenze/NN/benchmark_scripts/massive-data/slurm_download_bigann.sbatch'
```

Alternatively, use these files from a verified `fastEmbedR-extra` checkout
on the HPC. The batch file expects them at the path above.

## Check storage and network before submitting

Run this on the HPC login node. `--preflight-only` makes a HEAD request and
checks the free bytes on the destination filesystem; it downloads no vectors.
Use a **separate** data directory from campaign results.

```bash
cd /scratch/firenze/NN
test -f benchmark_scripts/massive-data/download_bigann_subset.py || exit 1
test -f benchmark_scripts/massive-data/slurm_download_bigann.sbatch || exit 1
export BIGANN_DATA_ROOT=/scratch/firenze/NN/Data/BigANN
mkdir -p "$BIGANN_DATA_ROOT" benchmark_logs
df -h "$BIGANN_DATA_ROOT"
python3 benchmark_scripts/massive-data/download_bigann_subset.py \
  turing --rows 10000000 --output-root "$BIGANN_DATA_ROOT" \
  --preflight-only
python3 benchmark_scripts/massive-data/download_bigann_subset.py \
  deep --rows 10000000 --output-root "$BIGANN_DATA_ROOT" \
  --preflight-only
```

Ten million rows require about 4.0 GB for Turing and 3.84 GB for DEEP,
plus the default 20 GB free-space reserve. Both full base files require
**784 GB together**, plus the reserve and substantial separate space for
graphs, PCA scores, embeddings, and checkpoints. Before submitting both,
require at least 804,000,000,016 free bytes on the destination filesystem
and check the account quota separately. The downloader checks filesystem
free space, not Slurm or project quota. Do not submit a full-data job on a
smaller filesystem.

For a full-data preflight, repeat the two commands above with
`--rows 1000000000`. Each reports `READY` only when that individual file
can fit. Those checks are not a substitute for the **combined** 804 GB
requirement.

The resulting file can be passed directly to
`fastEmbedR::massive_matrix("/path/to/base.10000000.fbin")`; no second,
headerless float32 copy is needed. Keep the dataset's original manifest with
the file when moving it between storage systems.

## Submit the downloads

The two array tasks may run together. Each requests one CPU, 16 GB of
memory, and a 48-hour wall limit. The downloader flushes and syncs each
64 MiB checkpoint, then releases cached file pages where supported. Before
resuming, it checks the final 64 MiB of an existing `.part` against the
same ETag-bound source and redownloads that tail if it differs. Neither
timeout nor an out-of-memory kill requires deleting the partial file.
The 48-hour limit is a Slurm resource request, not a downloader limit; a
site policy may cap it. Do not move or edit the partial file between runs.

```bash
cd /scratch/firenze/NN
export BIGANN_DATA_ROOT=/scratch/firenze/NN/Data/BigANN
job=$(sbatch --parsable \
  --export=ALL,BIGANN_ROWS=10000000,BIGANN_DATA_ROOT="$BIGANN_DATA_ROOT" \
  benchmark_scripts/massive-data/slurm_download_bigann.sbatch)
echo "Download job: $job"
```

After checking the terms, quota, and combined storage, substitute
`BIGANN_ROWS=1000000000` to download both complete base files. To download
only one, pass `--array=0` for Turing or `--array=1` for DEEP to `sbatch`.
After an interrupted billion-row transfer, rerun the same array tasks with
the same root and row count. First confirm there are no active downloader
jobs and inspect the `.part` and `.part.meta.json` files. The preflight
checks the remote ETag and remaining space without changing those files.
Only `DONE` plus a verified `manifest.json` means the data are complete.

```bash
squeue -j "$job"
sacct -X -j "$job" -o JobID,State,ExitCode,Elapsed,MaxRSS
find "$BIGANN_DATA_ROOT" -name manifest.json -print
```

Only a completed file with a manifest is eligible as benchmark input. The
`manifest.json` records its SHA-256; use `sha256sum` on the file to verify
it before analysis. Keep download time separate from PCA, KNN, and embedding
timings. A downloaded billion-row file is not itself evidence that any
billion-row package calculation succeeded.

## DEEP-20k functional smoke

`smoke_bigann_deep.R` tests the completed first 20,000 DEEP rows on CPU
and one CUDA GPU. It checks the `.fbin` descriptor, streamed PCA, sharded
KNN with a sampled exact-recall audit, fuzzy and compact-affinity graphs,
short full-graph UMAP and t-SNE optimizations, landmark UMAP and t-SNE,
and landmark Leiden. The separate two-GPU script tests sharded PCA score
projection and landmark projection; it does not claim multi-GPU full-graph
optimization. Both scripts require fastEmbedR 0.1 and reject `.part` input.
The ten UMAP epochs and fifteen t-SNE iterations are functional checks,
not converged embedding or speed/quality benchmarks.

The pilot uses a **separate** `deep/20000` download. It does not read or
modify the still-growing `deep/1000000000/*.part` file. Submit its download
and the CPU, one-GPU, and two-GPU checks using
`bash benchmark_scripts/massive-data/submit_bigann_deep_smoke.sh` on the
HPC. The launcher uses `afterok` dependencies on the prefix download. The batch
script is `slurm_smoke_bigann_deep.sbatch` with positional backend `cpu`,
`cuda`, or `cuda2`. Each job writes `stages.csv`, input/image SHA-256,
Slurm logs, and file-backed outputs under
`fastEmbedR-results/massive-data/deep20k/JOBID_BACKEND/` on the HPC.
CPU and GPU jobs are independent after the prefix download succeeds.

Passing this pilot would not establish performance, recovery from an
interrupted checkpoint, a memory boundary, or billion-row feasibility.

## Current Hugging Face evidence

The 2026-10-05 Hugging Face two-A10G calculation used **one million rows**
of a pinned SPACEV-1B prefix, not Turing or DEEP and not one billion rows.
Its PCA, KNN, UMAP, and t-SNE diagnostic results were printed, but the job
finished with an `ERROR` state. Do not use it as a completed billion-row
benchmark or a publication speed comparison. Job ID:
`6ac38ecb404719ba37654863`.
