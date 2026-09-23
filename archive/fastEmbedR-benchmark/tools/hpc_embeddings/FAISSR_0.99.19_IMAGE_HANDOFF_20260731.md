# faissR 0.99.19 Singularity image handoff

## Image identity

- faissR version: `0.99.19`
- faissR commit: `181735600f89f7d96e5bb5edfb7a48eca4f7466e`
- faissR source SHA-256:
  `60d5995f85ff32415ed1dee323df7172818ebdd460186928ef1cf7182403a3d2`
- KODAMA commit: `f6cdef85794d94619710a35f64462c95a02005e2`
- CUDA architectures: `75, 80, 86, 89, 90, 120`
- Image size: `5,228,199,936` bytes
- Image SHA-256:
  `d83076ae3452058a9d7721a737d82464239e5edc921112ff93a0ae1743794887`

## Paths

- Chiamaka:
  `/mnt/sata_ssd/fastEmbedR/singularity/fastembedr_cuda_faissR_0.99.19.sif`
- HPC:
  `/scratch/firenze/NN/singularity/fastembedr_cuda_faissR_0.99.19.sif`

The existing HPC `/scratch/firenze/NN/singularity/fastembedr_cuda.sif`
was not replaced.

## Validation on chiamaka

The following checks passed inside the image with `--nv`:

- FAISS CPU exact KNN;
- CUDA exact KNN;
- CUDA auto-selected KNN at target recall 0.99;
- GPU-resident `faissR::nn_gpu()` with zero result copies before explicit
  `faissR::gpu_knn_to_host()`;
- `fastEmbedR::precompute_knn()` with CUDA;
- full CUDA `fastEmbedR::umap()` and `fastEmbedR::opentsne()` smoke tests;
- KODAMA `data`/`graph` API;
- serialized `KODAMA.graph()` reuse by CPU and CUDA KNN and PLS-LDA with
  zero internal graph rebuilds.

The image also retains RcppHNSW 0.7.0, nabor 0.5.0, and rnndescent 0.2.0.

## Example HPC invocation

```bash
apptainer exec --nv \
  /scratch/firenze/NN/singularity/fastembedr_cuda_faissR_0.99.19.sif \
  Rscript -e 'library(faissR); print(packageVersion("faissR")); print(backend_info())'
```
