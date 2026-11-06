# Metal file-backed t-SNE input probes, 3 November 2026

Both bounded probes ran on Silvano's Apple M3 Ultra. The scripts and logs
are retained here and under `/Users/silvanopiazza/Documents/Stefano` on
the Mac. Each generated data file was created in `Stefano` and removed
after the run. Neither probe launched a full t-SNE fit.

| Probe | Result | SHA256 script | SHA256 log |
| --- | --- | --- | --- |
| `metal_mmap_buffer_probe_20261103.swift` | GPU read all 65,536 values from a 256 KiB memory-mapped file correctly. | `68344df4bf1d83db4c9ec3038baaa3871910da599a5b46f672a37baf08e30fd6` | `f958d96e43db47d8edfd2d00c9b0cf4ed09f0b235efacb1ea00404c64a049b57` |
| `metal_csr64_attraction_probe_20261103.swift` | A 3D Metal attraction kernel matched a CPU reference using memory-mapped 64-bit offsets, 32-bit targets, and float32 weights. | `32461ef9530b48557c85bd80501ac64a3b38de0dba7896d74f7d4d2f91e19a83` | `bbf8d37fb80ae35c0c30fbdf544a36ba6850411df4224f9b2ee4220cbe431600` |

The CSR test used four vertices and eight edges, with a logical edge base
of 2,147,483,670. This checks 64-bit offset arithmetic above the signed
32-bit limit and the subtraction needed for chunk-local edge buffers. It
does **not** test a physical graph with billions of edges, sustained SSD
throughput, or GPU memory pressure.

The reported Metal `maxBufferLength` is 179,357,827,072 bytes and the
recommended working set is 239,143,780,352 bytes. A full-graph t-SNE
implementation still needs the resident 2D/3D FFT repulsion joined to
chunked attraction, optimizer state, bounded allocation, checkpoint and
resume, and numerical and performance qualification. Its production graph
reader should keep 64-bit global offsets and convert to chunk-local edge
positions, since 100M rows at 30 neighbors exceed signed 32-bit edge
positions. These probes are design evidence, not a capability claim.

## Package CSR offset migration

The isolated package candidate now stores resident Metal t-SNE CSR row
offsets as `uint64_t` and reads them as `ulong` in both 2D and 3D update
kernels. The neighbor vertex IDs remain 32-bit. This removes the signed
32-bit edge-position limit from this shared native graph representation.
It does not by itself add a file-backed optimizer or prove a multi-billion
edge fit: resident KNN graph construction still materializes its inputs.

The candidate compiled and installed on the M3 Ultra in
`/Users/silvanopiazza/Documents/Stefano/metal-tsne-csr64-20261103`.
`test-tsne-fft-3d.R` and `test-metal-stages.R` passed; the former skipped
five CUDA-only checks. Generated compiler objects were removed and the
retained Mac test folder is 12 MB. The installed library SHA256 is
`fabf87debba83d3437d567419c92fb108141ef8dc2668e600acbe55ea4ff0178`.
Local copies of the two test logs are
`metal_tsne_csr64_test_3d_20261103.txt` (SHA256
`672eac4391715620f8222ec6087bc827450a872069f94fa3f1a02b8e3ab9fba8`)
and `metal_tsne_csr64_test_stages_20261103.txt` (SHA256
`2a1009aa0c4581511996187264cc779c780346ef7e01cbc54b44e3773d4cf42c`).

The 2D and 3D update kernels now also accept a first global row and a
64-bit edge base. They index the chunk-local CSR buffer by subtracting
that base while reading and writing the global layout row. Resident fits
pass zero for both parameters. The follow-up isolated Mac build at
`Stefano/metal-tsne-chunks-20261103` passed the same two regression files;
its installed library SHA256 is
`22bf4da40013b02108e12b064e7966466997d9ab239268a739a5c283c402b949`.
The existing regressions exercise the zero-base resident path. The
standalone mapped CSR probe tests nonzero 64-bit offset arithmetic, but
the package's nonzero chunk path still needs a file-backed caller and a
focused end-to-end test.
