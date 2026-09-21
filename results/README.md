# Derived benchmark results

`aggregate/` contains compact machine-readable summaries. `figures/` and
`tables/` are reproducible derivatives of those summaries.

These files do not replace the replicate-level result archive. Release claims
must be tied to the immutable identities in `aggregate/release_identity.txt`
and to the DOI recorded by the release gate. A blank, pending, or mismatched
identity means that the files are descriptive development results rather than
release-validating evidence.

The repository deliberately excludes raw datasets, generated nearest-neighbor
objects, PCA caches, Python NPZ files, individual layouts, container images,
and replicate worker directories.

Timing boundaries remain explicit:

- `r_public_function_total_call_sec`: complete R public-function call;
- `r_mediated_total_call_sec`: complete call through the R/Python boundary;
- `direct_python_fit_sec`: Python model-fit call only; and
- `direct_python_process_total_sec`: complete standalone Python process.

Only like-for-like timing boundaries should be used for speed ratios.
