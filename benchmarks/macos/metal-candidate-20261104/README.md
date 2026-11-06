# Metal candidate checks, 4 November 2026

The user stopped the older source-locked Mac panel-v6 to prioritize the
unfinished implementations. Its queue and worker were sent TERM. Two stopped
postprocess waiters were also terminated. A subsequent process inspection found
no panel-v6 benchmark processes. The FlowRepository checkpoint and parameter
table remain under
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-mac-20261031/results/m3-ultra-panel-v1/panel_v6_20261102_FlowRepository_FR-FCM-ZYRM_files`.
They contain 51 completed cases out of 84 planned cases. This is historical
baseline evidence, not validation of the current package candidate.

A fresh isolated package source was copied from
`in-progress/cuda-multigpu-3d-20261103` to
`/Users/silvanopiazza/Documents/Stefano/fastEmbedR-candidate-20261104/source`.
The transferred tar.xz SHA-256 is
`25c9ed2fb220de774bf7ed0570a5a7698c3c1f4ed67b14b0b99fa0b336870510`.
It built and installed under that folder's `library` with the existing faissR
library. The installed `fastEmbedR.so` SHA-256 is
`0edcf239b8e4c35daed8c0cae29b6e79124df7eb9c8b0c29c3b22f614a1703b0`.
The Mac's global R library was not replaced.

Focused actual-device checks:

- Resident landmark PCA, 100 × 16 synthetic input, 50 landmarks, 3 components:
  native Metal projection label; maximum difference from CPU projection of the
  same fitted loadings `5.230791e-07`. Passed the `1e-4` bound.
- Resident 3D Metal UMAP, Iris 150 × 4, 15 neighbors: trustworthiness
  `0.9737113`, optimizer backend `metal`. Passed the `0.9` bound.
- Fixed-graph Fashion-MNIST 5,000 paired UMAP quality diagnostic: CPU
  silhouettes for seeds 4/17/42 were `0.1983691`, `0.2003836`, `0.1998277`;
  scheduled Metal yielded `0.1741036`, `0.1939799`, `0.1717490`.
  This still fails the paired quality target. The printed diagnostic marker
  means that the script completed; it is not a quality pass.

Mac logs are in the isolated candidate folder as `install.log`,
`metal_pca_landmark_test.log`, `metal_umap_iris3d.log`, and
`metal_umap_fashion_quality.log`. Do not launch a new full Mac panel until the
Fashion quality gap and other candidate gaps are resolved and source locked.

The candidate also passed the installed-package `test-massive-leiden.R` and
`test-massive-louvain.R` files on the Mac. Those files include real Metal
file-backed full-graph Leiden/Louvain, contraction, connected-community and
checkpoint/resume checks on synthetic graphs. Logs are
`metal_file_leiden_test.log` and `metal_file_louvain_test2.log` in Stefano.
The first Louvain `test_file()` attempt lacked the package context and failed
on unqualified internal helper names; rerunning with `package="fastEmbedR"`
passed. This is device validation on small synthetic graphs, not a
publication-scale performance or biological-quality result.

A follow-up isolated candidate `fastEmbedR-candidate-20261104b` exposes
`refinement_epochs` for resident landmark UMAP, allowing explicit zero or a
non-negative count via the public API. Its transfer archive SHA-256 is
`3eb96347a4991141a799b9e8b6318b75d55bce69994236aab97bb04090dca932`.
It built in a separate Mac library. The complete focused `test-landmarks.R`,
`test-umap-init.R`, and `test-umap-metal-3d.R` files passed (the CUDA-only
initialization case was skipped on the Mac). An actual Metal 3D Iris call with
zero versus 20 refinement epochs reported the corresponding metadata, native
Metal refinement, and a nonzero layout change (`46.60831` summed absolute
coordinate difference). Logs are under the `b` candidate folder. This makes
refinement controllable for quality experiments; it does not resolve the
Fashion-MNIST Metal quality gap.

The new API control was used for a fixed, balanced 300-row subset of
Fashion-MNIST and MNIST (30 sampled rows per observed class, seed 733). The
source scripts in this directory match the Mac copies by SHA-256: Fashion
`e4e9504e5f176d4748f15b0481cadc6a78c89b7de8a14519f684a0d099527b93`;
MNIST `c00abf70346d3308b5e8b221d9fd32414a54bef9b72a193da5bd7960aa28542d`.
Their Mac logs are `fashion_landmark_refinement_v2.log` and
`mnist_landmark_refinement.log` under the `b` candidate folder. The first
Fashion attempt failed before calculation because the script assumed labels
0–9 while the stored file uses another coding; its failed log is preserved.
The versioned script samples the observed classes.

| Dataset | 3D Metal UMAP fit | Trustworthiness | Nearest-label accuracy |
| --- | --- | ---: | ---: |
| Fashion-MNIST | full | 0.97156 | 0.63667 |
| Fashion-MNIST | 50% landmarks, 0 epochs | 0.96604 | 0.60000 |
| Fashion-MNIST | 50% landmarks, 20 epochs | 0.94983 | 0.50000 |
| Fashion-MNIST | 50% landmarks, 50 epochs | 0.95821 | 0.57000 |
| Fashion-MNIST | 50% landmarks, 100 epochs | 0.96151 | 0.54667 |
| MNIST | full | 0.91865 | 0.69667 |
| MNIST | 50% landmarks, 0 epochs | 0.86311 | 0.60667 |
| MNIST | 50% landmarks, 20 epochs | 0.83117 | 0.51667 |
| MNIST | 50% landmarks, 50 epochs | 0.86810 | 0.58000 |
| MNIST | 50% landmarks, 100 epochs | 0.88191 | 0.60667 |

The best tested epoch count differs by dataset and metric. Zero epochs gave
the best Fashion trustworthiness and label accuracy; 100 improved MNIST
trustworthiness versus the 50-epoch default, but remained below full-data
quality. These tiny subsets do not justify a global default change or a
publication result. They motivate an explicit quality sweep across datasets
and landmark fractions. Full CPU and Metal trustworthiness on each same subset
were similar, so the observed gap is concentrated in the landmark route.
