# 3D landmark MNIST quality test, 4 November 2026

The [Hugging Face job](https://huggingface.co/jobs/tkcaccia/6aeaef140e0338d1bb7f93f5)
completed at 08:54:48 UTC on two A10Gs. The quality cases below use one GPU;
the same job also reran the previous small two-GPU device and quality tests.
It had an 18-minute server timeout and used the isolated fastEmbedR candidate
source patch SHA-256
`f5be1ad8b49cb5d60e164823a4bde6a2d3bf129d29debf5a012cf6a1cb4f159a`.

The exact runner and tests are `run-landmark.sh` and
`tests-landmark.tar.xz` (SHA-256
`eecb09071933630de213696064bcbf24524cba01eb4fee4be563f7fc355132f6`).
The quality script is `hf_landmark_mnist.R`. It downloaded the official public
MNIST NumPy archive and reused the fixed 300-row balanced selection and scoring
functions from the previous run. Each landmark case used 150 reference rows.

| 3D method | Fit | Trustworthiness | Preserve@15 | Label accuracy | Sampled KL | Seconds |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| t-SNE | full | 0.92654 | 0.56644 | 0.69667 | 0.75269 | 0.612 |
| t-SNE | 50% landmarks | 0.92776 | 0.54067 | 0.73667 | 1.23426 | 0.233 |
| UMAP | full | 0.92642 | 0.56267 | 0.71000 | 1.61686 | 0.432 |
| UMAP | 50% landmarks | 0.90182 | 0.46756 | 0.56667 | 1.88594 | 0.361 |

Both cases passed the test script's broad smoke threshold, but that threshold
allows a trustworthiness loss up to 0.1. Landmark UMAP lost 0.02460 in
trustworthiness and 0.14333 in label accuracy. Treat this as a quality gap to
investigate before using landmark UMAP as a manuscript result. The 300-row
run is too small for publication-scale performance claims. The elapsed seconds
are exploratory and include different computation paths.

The Chiamaka versioned attempts are documented separately; the user directed
this calculation away from Chiamaka while Bora is busy. UCT HPC was not used.
