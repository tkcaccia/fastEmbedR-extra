# Four completed CPU8 cases: manifest audit

The four resident CPU8 cases for FlowRepository and ImageNet features
finished with Slurm `COMPLETED 0:0`. This folder preserves their small JSON
manifests, the small source-locked plan and worker files, a read-only local
auditor, and its report. The case/input/worker/routes hashes, row counts,
precision, backend, effective cores, fit scope, timing fields, quality
ranges, cgroup peak RAM, and exact scheduler task identities passed.

Slurm's displayed array IDs and numeric job IDs differ by design. For
example, `1607318_27` has raw task ID `1607319`; the result's provenance
records the raw ID. `report.json` contains the verified mapping.

This is a **manifest audit**. The output RDS files were checked for existence
and nonzero size by remote file metadata, but their contents were not copied
or independently read. Do not use these four cases as a complete manuscript
cohort until output content and the full repeated matrix are audited.

The audit reads small files locally. It did not hash the container or dataset
on the HPC login node and performed no file-backed scientific work there.
