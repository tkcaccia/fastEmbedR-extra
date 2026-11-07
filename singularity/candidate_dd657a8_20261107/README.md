# Isolated streamed CUDA package install check

Package source is the detached local candidate commit `dd657a8` based on main
`535d071849945db3fa550d3c50f80633b91748cc`. The source archive SHA256 is
`0d6446a1404c6f35ee2c33a8fb5b9ead1fd9357be3766e693df71ce9bafe31e6`.
It was transferred to
`/scratch/firenze/NN/singularity/candidate_dd657a8_20261107`.

Compute job 1606609 completed successfully on a compute node. It checked
both source and the existing R 4.6 image hash there, installed the candidate
in a separate scratch library, and verified that the installed persistent
Python worker has SHA256
`deaa1ab627ad24fc20b17ce897ba32ef868e679c23ab39365add7d7ee5d16c4c`.
It loads the package and checks the public `graph_cluster()` export. No
file-backed or streaming scientific calculation is run on UCT HPC.

The job is an install/load gate only. It does not establish correct public
multi-GPU execution, quality, scaling, beyond-VRAM capacity, or GPU cleanup.
The package candidate is not merged into main pending those device checks.
