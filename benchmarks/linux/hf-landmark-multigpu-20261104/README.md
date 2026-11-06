# Resident CUDA landmark t-SNE multi-GPU device check

The isolated package candidate added a coordinated two-GPU reference fit
and sharded CUDA query projection for partial landmarks. A small 160-row
synthetic check passed both 2D and 3D on two A10G GPUs. This establishes
device execution only; real-dataset quality, scaling, and memory use remain
unqualified.

- Completed job: https://huggingface.co/jobs/tkcaccia/6aeb267b0e0338d1bb7fd329
- Candidate patch: `candidate.patch.xz`, SHA256
  `c05e5389d690ace23eb3241867c5c2259467d2c9eb4925eb7dbba919ce72704e`
- Runner: `run.sh`, SHA256
  `4c98e6a16b6637a322d300c77436168afd6a961ce528b68195ee8ee3934369f7`
- Terminal evidence: `terminal.log`, including two dimensionality pass
  markers and the final cleanup check.

An earlier job failed before calculation because the image lacked the `xz`
command. The completed runner uses Python's `lzma` module instead.
