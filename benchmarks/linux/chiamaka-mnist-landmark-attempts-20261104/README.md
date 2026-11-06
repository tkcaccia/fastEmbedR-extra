# Chiamaka MNIST landmark quality attempts, 4 November 2026

These two attempts did not produce scientific results. Both used the
isolated candidate on Chiamaka, the staged non-backup MNIST RData file,
and a 13-sample, two-minute idle gate before any GPU fit.

- `mnist_landmark3d_evidence_v1`: Admission passed and the container
  started, but the R script could not open MNIST because the dataset
  directory was not mounted into the container. Exit status was 1.
  All three post-test GPU-context checks were empty. No embedding fit ran.
- `mnist_landmark3d_evidence_v2`: A read-only mount check passed and a
  versioned runner began a new admission. The user then said Chiamaka
  was busy and directed this test to HPC/Hugging Face. The admission
  runner was stopped before its `started.txt` marker and before any
  scientific calculation. A subsequent exact-process and GPU-context
  check found no owned workload.

The `chiamaka-mnist-landmark-3d-20261104.R` script and both immutable
runner versions are retained for diagnosis. Do not retry either evidence
path in place. The Hugging Face replacement is a separate job.
