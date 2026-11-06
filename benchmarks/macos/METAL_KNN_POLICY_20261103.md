# FashionMNIST Metal KNN routing check, 3 November 2026

The isolated package candidate is installed in Silvano's
`/Users/silvanopiazza/Documents/Stefano/metal-knn-policy-20261103/Rlib`.
The source and test logs are in that folder. Generated compiler objects
were removed after installation; the folder is 12 MB.

The source change extends the one-call exact Metal KNN policy from at most
64 to at most 16,384 features, retaining the existing 50,000-row and
125-billion row-pair-feature work limits. The native exact kernel already
supports this dimension range. No native kernel was changed.

On the actual 5,000-row, 784-feature FashionMNIST panel dataset with 30
neighbors and Euclidean distance:

| Route | Seconds | Result |
| --- | ---: | --- |
| Explicit exact Metal | 0.117 | `native_metal_exact` |
| Explicit IVF Metal | 0.116 | `native_metal_ivf` |
| `precompute_knn(..., backend="metal")` | 0.126 | Selected exact; all neighbor IDs matched explicit exact |

IVF's mean row recall against exact was 0.98898, but its minimum row
recall was 0.26667. Exact search removes this KNN recall defect for this
shape without a material KNN time penalty. It does not resolve the
separate Metal UMAP optimizer quality failure, establish other dataset
speed, or qualify the full-pipeline manuscript gate.

The complete `test-native-knn.R` file passed on the M3 Ultra after fixing
its CPU-reference distance helper to preserve matrix dimensions. Six
CUDA-only checks were skipped on the Mac. Package source style and
`git diff --check` passed locally.

Evidence identities (SHA256):

- Installed `fastEmbedR.so`:
  `e4342324572109de083889e50358e35e8a7cd47718998bd9bbb29ec49cde1951`
- Device comparison log: `5e5f3e7ae3a38f521723ba17b389e435d5ae7b36f11058e6d50babdb76b5cd01`
- Focused package test log: `63589f93c5e6463de72a91b0cb10d7bc561ced674047b11f8bf83d685f138137`

The script is `metal_fashion_exact_knn_20261103.R` beside this file;
the Mac logs are `run.log` and `test-native-knn.log` in the isolated test
folder.
