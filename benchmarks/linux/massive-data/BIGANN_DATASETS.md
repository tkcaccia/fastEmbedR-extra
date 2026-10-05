# Turing-ANNS and DEEP downloads

This directory contains a resumable, standard-library-only downloader for
the Microsoft Turing-ANNS and Yandex DEEP base vectors listed by the
[Big ANN Benchmarks NeurIPS 2021 site](https://big-ann-benchmarks.com/neurips21.html).
The files are little-endian float32 `.fbin`: an eight-byte row/column header
followed by row-major values. A prefix is the **first** requested rows of
the official 1B file, not an independently sampled dataset. The downloader
updates the local header, writes a SHA-256 manifest, and leaves an incomplete
transfer as `.part` for the next run. It does not place vectors in Git.

| Dataset | Columns | Full base-file bytes | Terms |
| --- | ---: | ---: | --- |
| Turing-ANNS | 100 | 400,000,000,008 | [Research-only terms](https://big-ann-benchmarks.com/MSFT-Turing-ANNS-terms.txt) |
| Yandex DEEP | 96 | 384,000,000,008 | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |

Read the Turing terms before downloading or using it. Do not redistribute
Turing vectors in the replication archive. The source URL, ETag, dimensions,
row count, elapsed download time, and local SHA-256 are recorded in each
`manifest.json`. The ETag is source identity, not a cryptographic checksum.

## Copy the scripts to Chiamaka HPC

Run this from the Mac terminal. These are two small files, not the data:

```bash
SOURCE=/Users/stefano/Documents/fastEmbedR-extra/benchmarks/linux/massive-data
HOST=01481067@hex.uct.ac.za
ssh "$HOST" 'mkdir -p /scratch/firenze/NN/benchmark_scripts/massive-data /scratch/firenze/NN/benchmark_logs'
rsync -av \
  "$SOURCE/download_bigann_subset.py" \
  "$SOURCE/slurm_download_bigann.sbatch" \
  "$HOST:/scratch/firenze/NN/benchmark_scripts/massive-data/"
```

Alternatively, use these files from a verified `fastEmbedR-extra` checkout
on the HPC. The batch file expects them at the path above.

## Check storage and network before submitting

Run this on the HPC login node. `--preflight-only` makes a HEAD request and
checks the free bytes on the destination filesystem; it downloads no vectors.
Use a **separate** data directory from campaign results.

```bash
cd /scratch/firenze/NN
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

## Submit the downloads

The two array tasks run serially, using one CPU and 2 GB RAM each. The
12-hour limit applies to each task. If a task times out or a connection
breaks, rerun the same submission; its `.part` file resumes at the saved
byte offset. Do not move or edit that file between attempts.

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

## Current Hugging Face evidence

The 2026-10-05 Hugging Face two-A10G calculation used **one million rows**
of a pinned SPACEV-1B prefix, not Turing or DEEP and not one billion rows.
Its PCA, KNN, UMAP, and t-SNE diagnostic results were printed, but the job
finished with an `ERROR` state. Do not use it as a completed billion-row
benchmark or a publication speed comparison. Job ID:
`6ac38ecb404719ba37654863`.
