# Analysis workflow

The analysis has two stages.

1. `aggregate_linux_results.R` and `aggregate_macos_results.R` read local raw
   result archives and write compact CSV summaries.
2. `build_tables.R` and `build_figures.R` use only those aggregate CSV files.

This separation allows all publication tables and figures to be rebuilt
without distributing restricted datasets or multi-gigabyte worker outputs.

The release-locked JSS campaign additionally writes one `embedding.csv` and
one R-rendered `embedding.png` for every successful PCA, t-SNE, and UMAP
method. Build its Table 5 and method gallery from one campaign only:

```bash
Rscript analysis/build_table5_and_embedding_gallery.R \
  /absolute/path/to/campaign/results
```

The builder never searches older result trees. Its numerical table and plots
therefore use the same campaign identity and source coordinates.

```bash
make tables
make figures
make validate
```

The validation step checks required columns, non-negative finite runtimes,
timing-scope separation, output presence, and checksum coverage.
