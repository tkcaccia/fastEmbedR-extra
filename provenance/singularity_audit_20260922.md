# fastEmbedR CUDA Singularity audit

Audit date: 2026-09-22

## Scope

This report covers the image at:

`/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda.sif`

The audit was read-only. No Slurm jobs were submitted and no host software,
drivers, packages, or images were changed.

## Image identity

- Size: 5,625,618,432 bytes
- Modification time: 2026-09-22 15:24 SAST
- SHA-256:
  `59dc7a171d924557d0ec45a7960f83711235a0d46c78023b749c36dd3641a9fc`
- fastEmbedR: 0.1
- fastEmbedR source SHA-256:
  `85e695400694943cc0147cb20ff4a99a654bd9ce8c013dab2ddf41c3d6344f5a`
- faissR: 0.99.25
- faissR commit: `b33a70116887474a2ed70d84de0c80bb77e9db66`
- KODAMA: 0.99.6
- R used by fastEmbedR: 4.6.1
- Python: 3.12.13
- NumPy: 2.2.6
- openTSNE: 1.0.4
- umap-learn: 0.5.12
- RAPIDS cuML: 26.06.00
- Compiled CUDA architectures: 75, 80, 86, 89, 90, and 120

## Executive finding

The current image is capable of running fastEmbedR on CPU and CUDA. The
effective default `Rscript` is `/opt/r46/bin/Rscript`, fastEmbedR 0.1 loads
from `/opt/r46/lib/R/library`, all native libraries resolve, and a real CUDA
UMAP calculation reports the CUDA optimizer and
`native_cuda_cuvs_exact` KNN.

The previous HPC failure was caused by the benchmark launchers, which forced
`/opt/conda/bin/Rscript` and the Conda R library instead of using the R 4.6
installation into which fastEmbedR was installed. The old preflight therefore
reported that fastEmbedR was missing and every dependent job became
`DependencyNeverSatisfied`.

Although the current image works through its final environment block, it still
contains two R installations and many inherited, contradictory environment
blocks. This is fragile and should be corrected in the next clean image.

## Findings that should be fixed in the image

### 1. Two incompatible R installations are exposed

Severity: high

The image contains:

- `/opt/r46/bin/Rscript`: R 4.6.1, the intended runtime;
- `/opt/conda/bin/Rscript`: R 4.5.3, a secondary runtime.

fastEmbedR and faissR are installed only under the R 4.6 library:

- `/opt/r46/lib/R/library/fastEmbedR`
- `/opt/r46/lib/R/library/faissR`

The `float` package is duplicated under both R libraries. Explicitly invoking
the Conda R produces `WARNING: ignoring environment value of R_HOME`, mixes
the R 4.5 and R 4.6 library trees, and loads fastEmbedR with the warning that
it was built under R 4.6.1. Loading an R 4.6 compiled package into R 4.5 is not
a supported runtime contract even if a particular call appears to work.

Required correction:

1. Preferably remove R and R packages from the Conda environment while
   retaining Conda only for Python/RAPIDS dependencies.
2. If Conda R cannot be removed, hide its `R` and `Rscript` executables from
   the runtime PATH and do not include its R library in `R_LIBS*`.
3. Install every R package used by the benchmark into the single R 4.6
   library.
4. Add a build-time assertion that unqualified `Rscript` resolves to
   `/opt/r46/bin/Rscript` and loads fastEmbedR from `/opt/r46/lib/R/library`.

### 2. The embedded environment contains repeated stale blocks

Severity: high

`singularity inspect --environment` shows many inherited environment blocks.
Earlier blocks set:

- `PATH=/opt/conda/bin:...`
- `R_LIBS=/opt/conda/lib/R/library`
- `R_LIBS_USER=/opt/conda/lib/R/library`
- `R_PROFILE_USER=/opt/conda/lib/R/etc/Rprofile.user`

Later blocks override them with the intended R 4.6 paths. Singularity currently
sources the final block last, so the effective default works, but correctness
depends on layer order. This makes the image difficult to audit and easy to
break when another local image is used as a build base.

Required correction:

1. Rebuild from one clean definition rather than repeatedly extending old
   candidate images.
2. Emit one final `%environment` contract only.
3. Remove inherited R 4.5 environment declarations.
4. Add a validation that captures the effective `PATH`, `R_HOME`, `R_LIBS`,
   `.libPaths()`, and loaded package path under `--cleanenv`.

### 3. CUDA dependency prefixes are internally inconsistent

Severity: medium

The final environment sets `CUVS_HOME=/opt/conda`, while the validated patched
cuVS libraries are stored under `/opt/rapids/lib` and duplicated under
`/usr/local/cuda/lib`. Earlier inherited blocks instead set
`CUVS_HOME=/opt/rapids`.

The duplicate libraries are currently byte-identical:

- `libcuvs.so` SHA-256:
  `daf83f27031ed8f1e8224bbb288a9ff7c37ad3a069368525c572e8e7111f81d9`
- `libcuvs_c.so` SHA-256:
  `482dc32bf81796c733cc5df7b2bba80860de0c9cd8ffad71134386fc404ad528`

Nevertheless, the native fastEmbedR shared object resolves `libcuvs_c.so` from
`/usr/local/cuda/lib` and `libcuvs.so` from `/opt/rapids/lib`. This works now,
but future replacement of only one copy could create an ABI mismatch.

Required correction:

1. Select one authoritative cuVS prefix, preferably `/opt/rapids` for the
   patched libraries.
2. Set `CUVS_HOME` to that prefix.
3. Link and load both `libcuvs.so` and `libcuvs_c.so` from the same prefix.
4. Remove redundant copies or make them explicit symlinks to the authoritative
   files.
5. Verify the two loaded file paths and hashes during image validation.

### 4. The final runtime library path is incomplete for portability

Severity: medium

The final image environment includes `/usr/local/cuda/lib64`, but omits common
target-specific and compatibility locations such as:

- `/usr/local/cuda/targets/x86_64-linux/lib`
- `/usr/local/cuda/compat`
- `/.singularity.d/libs`

The current image resolves every dependency on Chiamaka, and Singularity
`--nv` supplies host-driver libraries. The omission can still make the image
sensitive to toolkit layout and container runtime behavior on the HPC.

Required correction:

Use a single ordered runtime path containing the R 4.6 runtime, the
authoritative RAPIDS/cuVS prefix, any required FAISS prefix, CUDA `lib64`, CUDA
target libraries, CUDA compatibility libraries, Conda libraries needed by
RAPIDS, and Singularity's injected driver-library directory. Confirm with
`ldd` that no package shared object has an unresolved dependency.

### 5. Build and runtime compiler policy is mixed

Severity: medium

The image exports `CUDAHOSTCXX` as a Conda compiler while also placing a custom
CUDA wrapper ahead of the system compiler. This may be intentional for a frozen
build, but it conflicts with the desired policy that the system compiler remain
ahead of Conda compiler wrappers and that `nvcc` use an explicitly compatible
host compiler.

Required correction:

1. Separate build-only compiler variables from runtime environment variables.
2. Do not export `CUDAHOSTCXX`, `PKG_CPPFLAGS`, or `PKG_LIBS` globally at
   runtime unless package compilation inside the image is an advertised use.
3. During the build, record the exact `nvcc`, host C++, C++, Fortran, OpenMP,
   BLAS, and LAPACK toolchains.
4. Validate package compilation with a minimal CUDA compile-and-link probe,
   not only the presence of `nvcc`.

### 6. Image metadata contains stale and ambiguous provenance

Severity: medium

The label set includes previous fastEmbedR commits and versions and the stale
label `FastPLSCompatibility: R-4.5-container-metadata-only` in an R 4.6.1
image. The generic OCI license label is `Apache-2.0`, although the image is a
collection of components with several licenses. Python comparator versions and
the FIt-SNE source commit are not captured in the labels shown by the audit.

Required correction:

1. Retain only current source identities as primary labels; move build lineage
   to a separate manifest if it is useful.
2. Remove stale R 4.5 and previous-release labels.
3. Record immutable versions or commits for FIt-SNE, openTSNE, umap-learn,
   cuML, CUDA, cuVS, RAFT, RMM, KODAMA, faissR, and fastEmbedR.
4. Add a third-party license manifest instead of implying that the complete
   image has a single Apache-2.0 license.
5. Save the definition file, build log, package source hashes, and image hash
   together.

### 7. The image lacks a self-contained runtime verification command

Severity: medium

The image has useful labels, but no single installed script verifies the R
runtime, package path, native linkage, and real CUDA execution. This allowed a
launcher to select the wrong R interpreter without a clear early failure.

Required correction:

Install a small validation command, for example
`/opt/fastembedr/bin/validate-fastembedr-image`, that:

1. asserts R 4.6.1 and the expected package versions;
2. prints package and DLL paths;
3. checks native shared libraries with `ldd`;
4. reports `fastEmbedR_capabilities()`;
5. runs a CPU smoke calculation;
6. when invoked with `--cuda`, runs a real CUDA calculation and verifies the
   returned optimizer and KNN backend metadata;
7. exits nonzero on any fallback or mismatch.

## Launcher defect already corrected

The HPC validation launchers used `/opt/conda/bin/Rscript` directly and
overrode the image's R library paths. They have been revised to use:

- `/opt/r46/bin/Rscript`
- `/opt/r46/lib/R/library`
- a complete explicit runtime-library path

The revised preflight also runs a finite UMAP calculation and checks the
returned optimizer and KNN metadata. CUDA cannot pass by falling back to CPU.
Preflight identity now records the R executable, R home, library paths, package
DLL hash, and externally computed image SHA-256.

The previous failed evidence is retained at:

- `/Users/stefano/HPC-firenze/NN/benchmark_logs/feR_JSS_pre_cpu_1360427.err`
- `/Users/stefano/HPC-firenze/NN/benchmark_logs/feR_JSS_pre_gpu_1360428.err`

## Validation completed on Chiamaka

The revised launchers were tested against the exact audited image.

CPU preflight:

- requested backend: `cpu`
- observed optimizer: `cpu_fuzzy_csr`
- observed KNN backend: `cpu`
- output dimensions: 512 by 2
- all layout values finite: yes

CUDA preflight:

- requested backend: `cuda`
- observed optimizer: `cuda`
- observed KNN backend: `native_cuda_cuvs_exact`
- output dimensions: 512 by 2
- all layout values finite: yes

Native linkage:

- unresolved libraries in `fastEmbedR.so`: none
- R BLAS/LAPACK: OpenBLAS 0.3.34 / LAPACK 3.12.0
- package DLL SHA-256:
  `b0830e0256deb790078f11a8f62e7c8e650da20db835d97962c820e705a3cd50`

## Rebuild acceptance criteria

The next image should be accepted only if all of the following pass under
`singularity exec --cleanenv`:

1. `command -v Rscript` returns `/opt/r46/bin/Rscript`.
2. Only the intended R library appears in `.libPaths()`.
3. fastEmbedR loads without warnings and from the intended library.
4. `ldd` reports no unresolved native dependencies.
5. CPU smoke metadata reports the CPU optimizer and CPU KNN.
6. CUDA smoke metadata reports the CUDA optimizer and CUDA KNN.
7. The CUDA smoke fails when the image is run without GPU passthrough; it must
   not silently use CPU.
8. The image definition, build log, source identities, dependency manifest,
   third-party notices, and SHA-256 are archived together.

