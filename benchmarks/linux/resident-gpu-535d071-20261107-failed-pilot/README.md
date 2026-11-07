# Preserved one-L40S pilot failure

Slurm job `1607281` used package commit
`535d071849945db3fa550d3c50f80633b91748cc` and the immutable image
whose compute-node SHA-256 was
`15b494004966c5e8ae4ada72db28024356cfa8a981333a37484ce75a09d08bf2`.
The job failed after 28 seconds with exit `1:0`, before starting the R worker
or creating a result directory. The stderr file was empty. Its stdout records
`image_verified` followed by an allocation-identity rejection.

The source-locked runner copied a two-GPU validation condition into its
one-GPU route: it required two distinct `SLURM_JOB_GPUS` and
`CUDA_VISIBLE_DEVICES` entries while also requiring exactly one entry in
each list. Thus every valid one-GPU allocation failed before calculation.
This failure says nothing about UMAP quality, performance, or GPU cleanup
after a scientific child, because no child was started.

The launch script, admission runner, case manifest, and logs here were
recovered read-only from the failed remote work directory. The unchanged R
worker, route manifest, and policy code are included with the v2 candidate;
none of those were invoked by this prelaunch failure. These files are
historical evidence; do not submit `gpu_case.sbatch` or modify the remote
originals.
The corrected candidate is in the separate `resident-gpu-535d071-20261107-v2`
directory. It needs an allocated-node pilot and full lifecycle audit before
any broader CUDA benchmark.
