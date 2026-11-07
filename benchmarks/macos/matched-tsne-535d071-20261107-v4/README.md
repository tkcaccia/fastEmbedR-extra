# Matched resident Mac t-SNE pilot v4

This versioned pilot addresses the cross-machine t-SNE control mismatch in
`docs/code-benchmarks-pages-audit-20261107.md`. It uses the already installed
535d071 package and the same COIL20 float32 file as Mac panel v2. It does not
change or resume that panel. The one-case runner checks the input, source
archive, and package binary hashes before calculation.

The pilot fits all rows on CPU with one worker. The controls are explicit:
perplexity 30, 250 early-exaggeration iterations, 300 subsequent iterations,
and `auto_config = FALSE`, matching the resident HPC v3 t-SNE worker. The R
worker rejects input or PCA scores that cease to be float32; it never converts
the dataset to double for timing. It records load, PCA preprocessing, fit,
quality, and output-write time separately, plus observed backend, effective
workers, package version, peak RSS, swap, and cleanup status.

`pilot-case.json` is a single immutable case and has a new output directory
under Stefano. Run it only after the currently active Mac mass41 diagnostic
has finished and its process group has cleared. Before interpreting timings,
the independent result audit must check `run.json`, `metrics.json`, hashes,
source version, memory, swap, and the full 2D output. One COIL20 case is a
method check, not a publication cohort; additional datasets, seeds, and CPU
and Metal lanes require new source-locked manifests.

Admission and parse checks:

```text
python3 -m unittest discover -s . -p 'test_*.py'
Rscript -e 'parse(file="worker.R")'
```
