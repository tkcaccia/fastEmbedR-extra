# Dataset acquisition and local layout

## Expected object format

Each benchmark dataset lives in its own local directory:

```text
Data/<dataset>/<dataset>.RData
Data/<dataset>/<dataset>_float32.RData
Data/<dataset>/MATERIALS_AND_METHODS.md
```

The standard R file should define `dataset`, a list with:

```r
dataset$data    # samples by variables matrix
dataset$labels  # vector/factor of length nrow(dataset$data)
```

The float32 companion is used only by fastEmbedR paths that accept
`float::float32`. Reference R packages must load the ordinary R matrix rather
than a converted float32 object. Generated KNN, PCA, Python NPZ, and validation
objects belong under `fastEmbedR-input/`, never under a replicate result
directory.

## Publication panel

| Dataset | Redistribution in this repository | Acquisition/preparation rule |
|---|---|---|
| COIL20 | No | Download from the Columbia Object Image Library provider or another source whose terms permit your use; record image preprocessing. |
| USPS | No | Obtain from OpenML or the original provider; optional Kaggle replication requires the user's own credentials and acceptance of Kaggle terms. |
| FashionMNIST | No | Download from the Zalando Research release; retain source checksums. |
| MNIST | No | Download the official IDX files or an equivalent documented public mirror; benchmark flattened 28 by 28 images. |
| MetRef | No | Load from the KODAMA R package and apply the documented zero-column removal, normalization, scaling, and donor-label procedure. |
| flow18 and mass41 | No | Obtain from the source accompanying the opt-SNE study/release and retain its labels and preprocessing metadata. |
| FlowRepository FR-FCM-ZYRM | No | Obtain from FlowRepository accession FR-FCM-ZYRM under its access terms; record channel selection and transformation. |
| Tabula Muris | No | Obtain from the Tabula Muris project/Figshare or Bioconductor `TabulaMurisData`; record QC, normalization, feature selection, PCA, and tissue labels. |
| Macosko2015 retina | No | Obtain from the Macosko et al. retinal single-cell release/GEO source; record filtering, normalization, feature selection, and labels. |
| ImageNet features | **Restricted** | The user must obtain ImageNet under ImageNet's terms and generate or lawfully obtain the documented feature representation. Do not upload images, labels tied to restricted files, or derived feature matrices unless redistribution is expressly permitted. |

This table is a reproducibility guide, not legal advice. Verify the current
provider terms before downloading or redistributing any dataset.

## Dataset identity

For every local file, record at minimum:

```bash
sha256sum Data/<dataset>/<file>
```

or on macOS:

```bash
shasum -a 256 Data/<dataset>/<file>
```

The benchmark manifest should also store `nrow`, `ncol`, label count, class
count, storage type, preprocessing date, source URL/accession, and the script
commit used to create the file. Checksums verify local identity but do not
authorize redistribution.

## Missing or restricted data

Benchmark scripts must not silently replace a missing dataset with another
matrix. A missing file should produce a dataset-level `unavailable` status and
continue with the remaining datasets. The result row should state the expected
path and acquisition instruction without revealing credentials or restricted
content.

The broader paper-inspired dataset inventory is available in
`data-manifests/paper_benchmark_datasets.csv` and
`data-manifests/paper_benchmark_datasets.md`.

