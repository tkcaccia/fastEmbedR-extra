# Prepared Mac file-backed input conversion

`convert_dataset.R` is a source-locked conversion candidate for the 11
comparison datasets. It checks the resident input digest and shape, writes
row-major float32 blocks to a new `.f32` file under Stefano, checks file
length and first/last rows through `massive_matrix()`, and records the output
digest and labels. It reserves at least 100 GiB of disk space. A 4-by-3
synthetic, two-row-block test passed on local R; actual Mac device and data
validation remains pending.

Do not run this conversion while the active resident Mac panel is measuring
timings. It would compete for CPU, RAM and SSD bandwidth. The file-backed
scientific worker and quality comparison must be qualified before a complete
file-backed lane is launched. This code is not used on the HPC.
