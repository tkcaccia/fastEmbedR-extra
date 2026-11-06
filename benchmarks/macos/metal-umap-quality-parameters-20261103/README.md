# Metal UMAP quality-parameter check, 3 November 2026

An isolated 12 KB experiment under
`/Users/silvanopiazza/Documents/Stefano/metal-umap-quality-parameters-20261103`
used FashionMNIST 5,000, a fixed 30-neighbor CPU graph and initialization,
400 epochs, and seeds 4, 17, and 42. The CPU reference used the package's
clean optimizer at learning rate 0.25. The native Metal snapshot optimizer
used the same fixed graph/start and varied negative sampling over
1, 2, 3, 5, or 8 and repulsion strength over 0.5, 1, or 2.

The [script](../metal_umap_quality_parameters_20261103.R),
[log](run.log), and [45-row CSV](results.csv) have matching local and
Mac SHA256 values. Script SHA256:
`e7814b47654bc6319cce1d249efbc6c7cb51857a9ff42e4bfe5cb4bc78bf30ac`.
CSV SHA256:
`db51b9c00dace7e45717819ffe94d175b14507b4ceb065fcd0a5cfe9cb8486f1`.
The tested isolated Mac library SHA256 was
`f1b9477c2deb02cb4e231dcf0a84f3072e65af4570d6ad22e893296e249a12c5`.
The source-locked Mac panel remained suspended.

None of the 15 settings passed the paired silhouette gate across all three
seeds. The best worst-seed difference was -0.02657 at negative sampling 1
and repulsion 2, versus the required minimum -0.01. This rules out these
bounded parameter changes as a quality fix for the Fashion snapshot path.
The grid did not test other datasets, longer training, or a new update
algorithm; no package default was changed.
