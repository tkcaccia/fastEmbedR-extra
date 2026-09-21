# Runtime summary

Direct-Python fit and R total-call timings are distinct boundaries.
Missing method-dataset combinations remain absent.

| Dataset | Method | Timing scope | Runs | Median seconds | Q1 | Q3 |
| --- | --- | --- | --- | --- | --- | --- |
| COIL-20 | fastEmbedR binary [CPU] | full_pipeline | 3 | 6.57 | 6.55 |  6.7 |
| COIL-20 | fastEmbedR fuzzy [CPU] | full_pipeline | 3 | 6.25 | 6.24 | 6.38 |
| COIL-20 | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 |   21 | 20.8 |   21 |
| COIL-20 | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 19.3 | 18.3 | 19.4 |
| COIL-20 | umap [CPU] | full_pipeline | 3 | 33.9 | 33.8 |   34 |
| COIL-20 | uwot default [CPU] | full_pipeline | 3 |   20 | 19.9 | 20.1 |
| COIL-20 | uwot fast SGD [CPU] | full_pipeline | 3 | 19.2 | 19.2 | 19.2 |
| COIL-20 | fastEmbedR binary [CUDA] | full_pipeline | 3 | 0.588 | 0.585 | 0.602 |
| COIL-20 | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 0.59 | 0.589 | 0.617 |
| COIL-20 | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 | 3.36 | 3.35 |  3.4 |
| COIL-20 | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 | 1.86 | 1.86 | 1.87 |
| Fashion-MNIST | fastEmbedR binary [CPU] | full_pipeline | 3 | 64.6 | 64.5 | 65.1 |
| Fashion-MNIST | fastEmbedR fuzzy [CPU] | full_pipeline | 3 | 31.9 | 31.8 | 31.9 |
| Fashion-MNIST | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 | 79.7 |   77 | 80.2 |
| Fashion-MNIST | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 77.2 | 73.2 | 77.5 |
| Fashion-MNIST | umap [CPU] | full_pipeline | 3 |  986 |  978 |  986 |
| Fashion-MNIST | uwot default [CPU] | full_pipeline | 3 | 66.1 |   66 | 66.2 |
| Fashion-MNIST | uwot fast SGD [CPU] | full_pipeline | 3 | 46.7 | 46.7 | 46.7 |
| Fashion-MNIST | fastEmbedR binary [CUDA] | full_pipeline | 3 | 1.06 | 1.05 | 1.06 |
| Fashion-MNIST | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 0.98 | 0.98 | 0.984 |
| Fashion-MNIST | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 | 4.13 | 4.13 | 4.23 |
| Fashion-MNIST | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 |  2.6 |  2.6 | 2.61 |
| FlowRepository | fastEmbedR binary [CUDA] | full_pipeline | 3 | 81.3 | 81.1 | 81.4 |
| FlowRepository | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 77.1 | 76.9 | 77.2 |
| FlowRepository | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 |  199 |  198 |  200 |
| FlowRepository | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 |  198 |  197 |  198 |
| ImageNet | fastEmbedR binary [CPU] | full_pipeline | 3 | 1182 | 1182 | 1184 |
| ImageNet | fastEmbedR fuzzy [CPU] | full_pipeline | 3 |  531 |  530 |  533 |
| ImageNet | uwot default [CPU] | full_pipeline | 3 | 2138 | 2135 | 2147 |
| ImageNet | uwot fast SGD [CPU] | full_pipeline | 3 | 1820 | 1779 | 1830 |
| ImageNet | fastEmbedR binary [CUDA] | full_pipeline | 3 |  533 |  520 |  551 |
| ImageNet | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 |  512 |  511 |  514 |
| ImageNet | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 |  327 |  326 |  328 |
| ImageNet | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 |  314 |  313 |  315 |
| MNIST | fastEmbedR binary [CPU] | full_pipeline | 3 | 61.5 | 61.3 | 61.5 |
| MNIST | fastEmbedR fuzzy [CPU] | full_pipeline | 3 | 29.3 | 29.3 | 29.4 |
| MNIST | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 | 83.4 | 83.1 | 84.2 |
| MNIST | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 81.8 | 81.6 | 82.3 |
| MNIST | umap [CPU] | full_pipeline | 3 |  939 |  922 |  942 |
| MNIST | uwot default [CPU] | full_pipeline | 3 |   68 | 67.8 | 68.1 |
| MNIST | uwot fast SGD [CPU] | full_pipeline | 3 | 48.8 | 48.8 | 49.1 |
| MNIST | fastEmbedR binary [CUDA] | full_pipeline | 3 | 1.06 | 1.06 | 1.06 |
| MNIST | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 0.973 | 0.96 | 0.986 |
| MNIST | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 |  4.1 | 4.09 | 4.12 |
| MNIST | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 | 2.57 | 2.57 | 2.58 |
| MetRef | fastEmbedR binary [CPU] | full_pipeline | 3 | 0.853 | 0.831 | 0.855 |
| MetRef | fastEmbedR fuzzy [CPU] | full_pipeline | 3 | 0.599 | 0.585 | 0.615 |
| MetRef | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 | 15.1 | 14.7 | 15.1 |
| MetRef | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 12.5 | 12.3 | 12.7 |
| MetRef | umap [CPU] | full_pipeline | 3 | 3.19 | 3.17 | 3.35 |
| MetRef | uwot default [CPU] | full_pipeline | 3 | 1.92 | 1.91 | 1.96 |
| MetRef | uwot fast SGD [CPU] | full_pipeline | 3 | 1.61 |  1.6 | 1.61 |
| MetRef | fastEmbedR binary [CUDA] | full_pipeline | 3 | 0.567 | 0.56 | 0.567 |
| MetRef | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 0.544 | 0.542 | 0.554 |
| MetRef | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 | 3.01 | 3.01 | 3.01 |
| MetRef | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 |  1.8 |  1.8 |  1.8 |
| Retina | fastEmbedR binary [CPU] | full_pipeline | 3 | 32.8 | 32.8 | 32.9 |
| Retina | fastEmbedR fuzzy [CPU] | full_pipeline | 3 | 10.1 | 10.1 | 10.1 |
| Retina | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 |   51 | 50.6 | 51.6 |
| Retina | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 49.5 | 49.4 | 49.6 |
| Retina | umap [CPU] | full_pipeline | 3 |  364 |  359 |  366 |
| Retina | uwot default [CPU] | full_pipeline | 3 | 25.6 | 25.5 | 25.7 |
| Retina | uwot fast SGD [CPU] | full_pipeline | 3 | 12.6 | 12.5 | 12.6 |
| Retina | fastEmbedR binary [CUDA] | full_pipeline | 3 | 0.672 | 0.667 | 0.673 |
| Retina | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 0.611 | 0.607 | 0.634 |
| Retina | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 | 3.16 | 3.15 | 3.21 |
| Retina | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 | 1.93 | 1.93 | 1.94 |
| Tabula Muris | fastEmbedR binary [CPU] | full_pipeline | 3 | 65.5 | 65.2 | 65.5 |
| Tabula Muris | fastEmbedR fuzzy [CPU] | full_pipeline | 3 | 20.4 | 20.3 | 20.5 |
| Tabula Muris | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 | 90.4 | 88.8 | 93.9 |
| Tabula Muris | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 85.8 | 85.7 | 87.8 |
| Tabula Muris | umap [CPU] | full_pipeline | 3 |  734 |  733 |  737 |
| Tabula Muris | uwot default [CPU] | full_pipeline | 3 | 70.2 |   70 | 70.3 |
| Tabula Muris | uwot fast SGD [CPU] | full_pipeline | 3 | 44.5 |   44 | 45.1 |
| Tabula Muris | fastEmbedR binary [CUDA] | full_pipeline | 3 | 0.897 | 0.891 | 0.912 |
| Tabula Muris | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 0.811 | 0.807 | 0.826 |
| Tabula Muris | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 | 3.64 | 3.62 | 3.64 |
| Tabula Muris | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 | 2.37 | 2.36 | 2.37 |
| USPS | fastEmbedR binary [CPU] | full_pipeline | 3 | 8.26 | 8.26 | 8.29 |
| USPS | fastEmbedR fuzzy [CPU] | full_pipeline | 3 | 3.96 | 3.95 | 3.96 |
| USPS | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 | 22.9 | 22.5 | 23.2 |
| USPS | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 21.4 | 20.9 | 21.4 |
| USPS | umap [CPU] | full_pipeline | 3 | 78.3 | 77.8 | 81.5 |
| USPS | uwot default [CPU] | full_pipeline | 3 | 8.32 | 8.24 | 8.36 |
| USPS | uwot fast SGD [CPU] | full_pipeline | 3 | 5.84 | 5.83 | 5.85 |
| USPS | fastEmbedR binary [CUDA] | full_pipeline | 3 | 0.563 | 0.559 | 0.57 |
| USPS | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 0.57 | 0.562 | 0.57 |
| USPS | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 | 2.98 | 2.98 | 2.99 |
| USPS | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 | 1.76 | 1.76 | 1.77 |
| flow18 | fastEmbedR binary [CPU] | full_pipeline | 3 |  643 |  641 |  643 |
| flow18 | fastEmbedR fuzzy [CPU] | full_pipeline | 3 |  221 |  220 |  222 |
| flow18 | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 | 1143 | 1106 | 1154 |
| flow18 | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 1127 | 1109 | 1147 |
| flow18 | uwot default [CPU] | full_pipeline | 3 | 1007 | 1006 | 1008 |
| flow18 | uwot fast SGD [CPU] | full_pipeline | 3 |  689 |  688 |  690 |
| flow18 | fastEmbedR binary [CUDA] | full_pipeline | 3 | 2.57 | 2.57 | 2.58 |
| flow18 | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 1.76 | 1.76 | 1.78 |
| flow18 | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 | 12.1 |   12 | 12.1 |
| flow18 | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 | 10.7 | 10.6 | 10.8 |
| mass41 | fastEmbedR binary [CPU] | full_pipeline | 3 |  648 |  648 |  650 |
| mass41 | fastEmbedR fuzzy [CPU] | full_pipeline | 3 |  214 |  214 |  215 |
| mass41 | Python umap-learn via R (total call) [CPU] | r_mediated_total_call | 3 | 1118 | 1085 | 1119 |
| mass41 | Python umap-learn direct (fit only) [CPU] | direct_python_fit | 3 | 1122 | 1091 | 1128 |
| mass41 | uwot default [CPU] | full_pipeline | 3 |  662 |  658 |  662 |
| mass41 | uwot fast SGD [CPU] | full_pipeline | 3 |  348 |  347 |  349 |
| mass41 | fastEmbedR binary [CUDA] | full_pipeline | 3 |    3 | 2.96 | 3.02 |
| mass41 | fastEmbedR fuzzy [CUDA] | full_pipeline | 3 | 2.09 | 2.09 |  2.1 |
| mass41 | RAPIDS cuML UMAP via R (total call) [CUDA] | r_mediated_total_call | 3 | 9.58 | 9.53 | 9.63 |
| mass41 | RAPIDS cuML UMAP direct (fit only) [CUDA] | direct_python_fit | 3 | 8.14 | 8.14 | 8.15 |
| COIL-20 | FIt-SNE [CPU] | full_pipeline | 3 | 18.8 | 18.7 | 19.6 |
| COIL-20 | Rtsne [CPU] | full_pipeline | 3 | 5.05 | 5.05 | 5.06 |
| COIL-20 | fastEmbedR t-SNE [CPU] | full_pipeline | 3 | 8.72 | 8.62 | 8.77 |
| COIL-20 | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 3 | 36.6 | 35.3 | 38.6 |
| COIL-20 | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 |   31 | 30.3 |   32 |
| COIL-20 | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 |  6.4 |  6.4 | 6.46 |
| COIL-20 | RAPIDS cuML t-SNE via R (total call) [CUDA] | r_mediated_total_call | 3 | 5.81 | 5.81 | 6.14 |
| COIL-20 | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 | 2.11 | 2.11 | 2.12 |
| Fashion-MNIST | FIt-SNE [CPU] | full_pipeline | 3 | 80.7 | 80.3 | 83.2 |
| Fashion-MNIST | Rtsne [CPU] | full_pipeline | 3 | 68.5 | 68.1 | 68.8 |
| Fashion-MNIST | fastEmbedR t-SNE [CPU] | full_pipeline | 3 |   44 | 43.4 | 44.6 |
| Fashion-MNIST | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 3 |  120 |  120 |  122 |
| Fashion-MNIST | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 |  109 |  109 |  111 |
| Fashion-MNIST | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 | 1.93 | 1.92 | 1.98 |
| Fashion-MNIST | RAPIDS cuML t-SNE via R (total call) [CUDA] | r_mediated_total_call | 3 | 6.78 | 6.65 | 7.82 |
| Fashion-MNIST | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 | 2.91 | 2.86 | 2.94 |
| FlowRepository | FIt-SNE [CPU] | full_pipeline | 3 | 3059 | 3057 | 3075 |
| FlowRepository | fastEmbedR t-SNE [CPU] | full_pipeline | 3 | 1315 | 1313 | 1324 |
| FlowRepository | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 | 90.7 | 90.6 |   91 |
| FlowRepository | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 |  779 |  766 |  780 |
| ImageNet | FIt-SNE [CPU] | full_pipeline | 3 | 1987 | 1986 | 1989 |
| ImageNet | Rtsne [CPU] | full_pipeline | 3 | 13820 | 13778 | 13848 |
| ImageNet | fastEmbedR t-SNE [CPU] | full_pipeline | 3 |  490 |  488 |  490 |
| ImageNet | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 |  519 |  507 |  523 |
| ImageNet | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 |  166 |  164 |  168 |
| MNIST | FIt-SNE [CPU] | full_pipeline | 3 | 88.7 | 88.3 | 88.8 |
| MNIST | Rtsne [CPU] | full_pipeline | 3 | 93.8 | 93.8 | 94.5 |
| MNIST | fastEmbedR t-SNE [CPU] | full_pipeline | 3 | 43.3 | 43.1 | 43.6 |
| MNIST | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 3 |  156 |  156 |  157 |
| MNIST | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 |  149 |  148 |  151 |
| MNIST | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 | 1.91 |  1.9 | 1.95 |
| MNIST | RAPIDS cuML t-SNE via R (total call) [CUDA] | r_mediated_total_call | 3 | 6.43 | 6.42 | 6.44 |
| MNIST | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 | 2.72 | 2.71 | 2.72 |
| MetRef | FIt-SNE [CPU] | full_pipeline | 3 |  4.5 | 4.25 | 4.56 |
| MetRef | Rtsne [CPU] | full_pipeline | 3 | 1.01 | 1.01 | 1.06 |
| MetRef | fastEmbedR t-SNE [CPU] | full_pipeline | 3 | 1.73 | 1.68 | 1.74 |
| MetRef | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 3 | 18.3 | 18.1 | 22.2 |
| MetRef | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 | 15.6 | 14.6 | 15.7 |
| MetRef | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 |  0.7 | 0.686 | 0.723 |
| MetRef | RAPIDS cuML t-SNE via R (total call) [CUDA] | r_mediated_total_call | 3 | 5.05 | 5.02 | 5.05 |
| MetRef | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 | 1.59 | 1.59 | 1.59 |
| Retina | FIt-SNE [CPU] | full_pipeline | 3 | 21.8 | 21.8 | 21.8 |
| Retina | Rtsne [CPU] | full_pipeline | 3 | 34.9 | 34.6 | 35.1 |
| Retina | fastEmbedR t-SNE [CPU] | full_pipeline | 3 | 11.7 | 11.4 | 11.7 |
| Retina | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 3 | 75.3 | 72.8 | 78.1 |
| Retina | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 |   66 | 64.2 | 67.6 |
| Retina | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 | 0.905 | 0.893 | 0.95 |
| Retina | RAPIDS cuML t-SNE via R (total call) [CUDA] | r_mediated_total_call | 3 | 5.67 | 5.66 | 6.02 |
| Retina | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 | 2.26 | 2.26 | 2.27 |
| Tabula Muris | FIt-SNE [CPU] | full_pipeline | 3 | 45.9 | 45.9 | 47.6 |
| Tabula Muris | Rtsne [CPU] | full_pipeline | 3 | 77.8 | 77.2 | 78.4 |
| Tabula Muris | fastEmbedR t-SNE [CPU] | full_pipeline | 3 | 30.2 |   30 | 30.5 |
| Tabula Muris | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 3 | 94.4 | 92.9 | 97.8 |
| Tabula Muris | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 | 87.9 | 87.7 |   90 |
| Tabula Muris | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 | 3.05 | 3.05 | 3.11 |
| Tabula Muris | RAPIDS cuML t-SNE via R (total call) [CUDA] | r_mediated_total_call | 3 |  6.2 | 6.19 | 6.21 |
| Tabula Muris | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 |  2.7 | 2.68 | 2.73 |
| USPS | FIt-SNE [CPU] | full_pipeline | 3 | 14.7 | 14.7 | 15.2 |
| USPS | Rtsne [CPU] | full_pipeline | 3 | 8.89 | 8.72 | 8.96 |
| USPS | fastEmbedR t-SNE [CPU] | full_pipeline | 3 | 7.32 | 7.24 | 7.32 |
| USPS | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 2 | 47.8 | 47.1 | 48.5 |
| USPS | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 | 44.5 |   44 | 44.5 |
| USPS | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 | 0.73 | 0.725 | 0.767 |
| USPS | RAPIDS cuML t-SNE via R (total call) [CUDA] | r_mediated_total_call | 3 | 5.36 | 5.35 | 5.36 |
| USPS | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 | 1.94 | 1.94 | 1.95 |
| flow18 | FIt-SNE [CPU] | full_pipeline | 3 |  397 |  389 |  397 |
| flow18 | Rtsne [CPU] | full_pipeline | 3 | 1585 | 1544 | 1613 |
| flow18 | fastEmbedR t-SNE [CPU] | full_pipeline | 3 |  179 |  178 |  179 |
| flow18 | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 3 |  623 |  595 |  640 |
| flow18 | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 |  610 |  605 |  618 |
| flow18 | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 | 5.39 | 5.39 | 5.47 |
| flow18 | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 | 34.4 | 34.3 | 34.4 |
| mass41 | FIt-SNE [CPU] | full_pipeline | 3 |  330 |  330 |  331 |
| mass41 | Rtsne [CPU] | full_pipeline | 3 | 1604 | 1568 | 1693 |
| mass41 | fastEmbedR t-SNE [CPU] | full_pipeline | 3 |  165 |  164 |  166 |
| mass41 | Python openTSNE via R (total call) [CPU] | r_mediated_total_call | 3 |  577 |  534 |  605 |
| mass41 | Python openTSNE direct (fit only) [CPU] | direct_python_fit | 3 |  572 |  556 |  588 |
| mass41 | fastEmbedR t-SNE [CUDA] | full_pipeline | 3 | 5.68 | 5.68 | 5.75 |
| mass41 | RAPIDS cuML t-SNE direct (fit only) [CUDA] | direct_python_fit | 3 | 33.3 | 33.1 | 33.3 |
