# Independent CPU and Metal development pilots, 2026-11-05

These are single-seed checks of the current public API, not the formal JSS
benchmark cohort. The Mac jobs ran separately, never concurrently. All Mac
inputs and outputs are under `/Users/silvanopiazza/Documents/Stefano`.
After the runs, the installed Mac package library binary and staged source
build binary matched at SHA256
`946fc2ecf073a0e0863ad8a709fa6d5911cfece8f2fe60e88cd3245d0f43d9ce`;
the source archive `source.tar.xz` matched the package hash recorded below,
and its install log ended with `DONE (fastEmbedR)`.

| Lane | Source and input | Terminal result | Selected observations |
| --- | --- | --- | --- |
| Mac MNIST CPU/Metal | Installed isolated package archive SHA256 `18902d45dd0a6d0278f52d3712e8892a38d6ec16516644fc9ee2114f5be92973`; input SHA256 `0e1fefab430cded89c2c36871540aea87deee1a1316e1a7d6ea4d31c07f835b0`; 70,000 × 784 | 12/12 cases passed; exit 0; 71.615 s total | 2D t-SNE trustworthiness CPU/Metal 0.93172/0.93526; UMAP 0.94323/0.94300. |
| Mac Fashion-MNIST CPU/Metal | Same package archive; input SHA256 `7be6826c092c19aaaf47b97b602e74f42d2b9ba0a61ecda2de0c91cdbc6b4006`; 70,000 × 784 | 12/12 cases passed; exit 0; 70.481 s total | 2D t-SNE trustworthiness CPU/Metal 0.96553/0.96645; UMAP 0.97521/0.97510. A separate paired fixed-graph quality check still shows Metal UMAP silhouette below CPU. |
| Mac MetRef CPU/Metal | Same package archive; input SHA256 `5ccba0b55e6e39b9487d4f082c2dc8933dba894340fa5174ac1f9b6623bd6996`; 873 × 375 | 12/12 cases passed; exit 0; 6.031 s total | 2D t-SNE trustworthiness CPU/Metal 0.90355/0.89372; UMAP 0.87946/0.88639. The t-SNE difference needs repeated seeds before interpretation. |
| Mac Tabula Muris CPU/Metal | Same package archive; input SHA256 `f2fd5cc7f577f39f3e993d00bfcd5487861c646bc053bece39fad44382221116`; 100,102 × 50 | 12/12 cases passed; exit 0; 88.357 s total | 2D t-SNE trustworthiness CPU/Metal 0.92877/0.93025; UMAP 0.90073/0.90115. Four-core UMAP trustworthiness was 0.88691 and needs repeated quality checks. |
| Mac Tabula Muris 3D CPU/Metal | Same package and input as the 2D row; script SHA256 `afc9662f051ee21fbe0d445183e2b97978c1ac330751e17462ff3b0a30f770b1` | Six cases passed; exit 0; 435.229 s total | 3D t-SNE CPU/Metal fit 355.3/13.383 s, trustworthiness 0.93481/0.93638. 3D UMAP CPU1/CPU4/Metal fit 28.634/25.531/1.450 s, trustworthiness 0.90369/0.90434/0.91034. |
| HPC USPS resident CPU | Immutable b825116 image; source commit `b8251168e3b77093452876c10e1a79861d9660e5`; previously verified image SHA256 `144b878f42b8c10f2dc9bc3ee422c51caf5a090049c0f89027fdc27ad1f34773`; input SHA256 `b4cc55441bde1e61a3588bba172762e11d14463a06b1869d2bb3d16e719d6811`; 11,000 × 256 | Five independent 4-core jobs 1579292–1579296 completed 0:0 | Fit times: PCA 0.110 s, t-SNE 9.708 s, UMAP 2.547 s, Louvain 0.866 s, Leiden 1.135 s. No file-backed or streaming science. |

Mac source directories: `fastEmbedR-mnist-unified-pilot-20261105`,
`fastEmbedR-fashion-unified-pilot-20261105`, and
`fastEmbedR-metref-unified-pilot-20261105`, and
`fastEmbedR-tabula-unified-pilot-20261105`, each containing `run.R`,
`runner.py`, `run.log`, `metrics.csv`, and `exit.json`. The MetRef run and
runner SHA256 values are `c4f27b09602323e20934e1973bc0347f00e7838902364e0cc133f34d17490beb`
and `95e48f75222c4e88783db3c9d5899d426e9cdc457d1998e9fc490cdfbaf3e899`.
The Tabula Muris run and runner SHA256 values are
`b2c761fad15c58abfc673d54c7dd29b8d14d31218803af014617d134e9955035`
and `bd6e1745b38c6d68c431cf1937ac8535e033daa7c0ea2640dcbd44d7c60ea067`.
The separate 3D source directory is `fastEmbedR-tabula-3d-pilot-20261105`;
its runner SHA256 is
`1aa28e3caa85302cf7685ebce37d310553665669e3666bf581bfeecca13ff634`.
HPC source and results:
`/scratch/firenze/NN/benchmarks/resident_b825116_usps_20261105`.

Interpretation limits: one seed and one repetition; CPU/Metal Mac package and
HPC image are different source versions; some clustering and fixed-graph UMAP
quality varies by algorithm route. Do not pool these as a final comparison or
use them to support manuscript performance claims. Formal cases require a
frozen source cohort, repeated timings, multiple quality seeds, peak memory,
device metadata, and the full method/backend/storage/landmark matrix.

Benchmark-code audit finding: the current pilot hard-codes 30 PCA components
and rejects fewer than 30 input columns. This is valid for MNIST,
Fashion-MNIST, MetRef, and Tabula Muris, but invalid for mass41
(965,282 rows × 14 columns) and flow18 (1,000,021 rows × 11 columns).
Those datasets need explicit, source-locked rank profiles and a separate
resource envelope before launch. Silently dropping them or using the
30-component script would be wrong.

The pilot runner writes the expected package archive hash as a constant,
but does not recompute it or the installed DLL hash at admission. The
post-run check above strengthens this cohort's provenance; the formal
runner must independently verify both identities before each case.

A separate read-only audit script,
`benchmarks/macos/audit_unified_pilot_v1.R` (SHA256
`c24b0e825b2de0f3dd5b6494646fcce3e70a7e7e6b707e596beceefe7f6d841b`),
passed on COIL20, USPS, MNIST, Fashion-MNIST, MetRef, and Tabula Muris
2D pilots (12 cases each) and the Tabula Muris 3D pilot (six cases), for
78 cases total. It rechecked the actual input, source archive, staged
and installed DLL identities, every output row count and embedding
dimension, and effective Metal backend metadata. Four-core UMAP reported
four effective workers. The clustering objects report four requested
workers but do not expose an observed effective worker count, so their
multi-CPU execution remains unverified by this audit.
A negative check gave the MetRef result directory the USPS input file;
the audit rejected the identity mismatch before reading fit results.

Audit v2 (SHA256
`56db8ef14bbef58c88df0ed2d8db2e09b695f12af159cf46472dab03ca2eaf52`)
also checked native clustering's `effective_cpu_workers` and
`parallel_mode` fields, plus effective workers for 3D UMAP. It passed
all six 2D pilots and the Tabula Muris 3D pilot. The earlier statement
that clustering effective worker counts were unavailable refers only to
the v1 audit's inspection of `parameters`; the native result field was
present and reports one or four as requested in these pilots.
