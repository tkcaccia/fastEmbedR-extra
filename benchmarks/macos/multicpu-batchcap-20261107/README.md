# Multi-CPU file-backed clustering batch-size diagnostic

This staged Mac experiment compares the source-locked baseline with a candidate
that raises the proposal batch cap from 65,536 to 1,048,576 edges. Build each
package into its own library under Stefano after the active mass41 t-SNE job
ends. Run the same script once per library and keep the outputs separate.

The experiment reuses two existing file-backed fuzzy graphs under Stefano:
100,000 vertices with 30 neighbors and 50,000 vertices with 200 neighbors.
Pass their distinct graph prefixes as the third and fourth script arguments.
Pass the expected MD5 of the installed `fastEmbedR` native library as the
fifth argument; the script rejects a different build before calculation.
It measures Louvain and Leiden with 1, 2, 4, 8 and 16 CPU workers, three
repeats each. It records elapsed time, actual worker count, label SHA-256,
community count, modularity, and the installed native-library MD5. A change
must preserve exact clustering labels and modularity across all core counts
and repeats before any speed claim. Record peak resident memory with the Mac
process monitor or `/usr/bin/time -l` for each library run.

This is not a publication benchmark or a qualified performance improvement.
The script has been syntax checked locally; it has not run on the Mac.
Its SHA-256 is
`f5371a6cddf299fe16f615fa3a05988fb53297486b3a007b681762fcbd920e8a`.
