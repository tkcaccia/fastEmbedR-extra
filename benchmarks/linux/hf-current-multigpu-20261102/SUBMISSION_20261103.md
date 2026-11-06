# Hugging Face two-GPU qualification submission

- Job: `tkcaccia/6ae9852e0e0338d1bb7ef8df`
- URL: <https://huggingface.co/jobs/tkcaccia/6ae9852e0e0338d1bb7ef8df>
- Submitted: 2026-11-03 06:54:38 UTC
- Account: `tkcaccia`
- Flavor: `a10g-largex2` (two A10G GPUs), provider-selected region
- Docker image: `rapidsai/base:25.06a-cuda12.8-py3.12`
- Server timeout: 1800 seconds
- User-approved maximum spend: US$2
- Pricing checked 2026-11-03: US$3/hour, so 30 billed minutes cost US$1.50; see <https://huggingface.co/docs/hub/jobs-pricing>
- Source patch SHA256: `b45bf0aaba50036c0b079d5a60a66b78117e40ca49ffb3f7216ab2964bb75cce`
- Test bundle SHA256: `e8406cefead57f9e3b0a5fb16108ece75959b181ab0817de9ac91c16ebc5c89e`
- Runner SHA256: `6cbe6f6901d376874cafe81de794f11eddbb57b59c88c15014b3e175fa4ec969`

First inspection at about 06:55 UTC: `SCHEDULING`, pulling container image.
This file records submission, not a qualification result. Inspect the job and
its logs before reporting any pass or failure.

## Bounded retry

After the image setup failure and successful same-image CPU preflight, the
corrected runner was submitted as
`tkcaccia/6ae986550e0338d1bb7ef9bf` with the same two-A10G flavor
and 1800-second server timeout. Job URL:
<https://huggingface.co/jobs/tkcaccia/6ae986550e0338d1bb7ef9bf>.
It was `SCHEDULING` at submission. Runner SHA256:
`281c503aadc943e3b752033d5a725f9afd5b17055ce8c83aff9002a514173391`.
This retry shares the user's US$2 total cap with the first attempt.
No result is claimed until terminal logs are audited.

## Terminal audit

The retry completed at 2026-11-03 07:04:40 UTC. All bounded cases passed,
including NCCL, exact two-GPU KNN, 3D two-GPU UMAP, 2D two-GPU t-SNE,
two-GPU PCA, landmark PCA projection, Louvain, Leiden, and a separate
single-GPU 3D landmark t-SNE. Full log and checksum-verified CSV tables:
[evidence-20261103](evidence-20261103/README.md).
The Jobs API subsequently listed no running jobs.
