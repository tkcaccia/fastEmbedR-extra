# Mac resident panel continuation controller

The source-locked 535d071 v2 panel stopped after case 460. Its 965,282-row
one-core 3D t-SNE fit exceeded the reviewed two-hour limit. The runner
recorded `timed_out=true` and `cleanup_clear=false`, so the queue correctly
stopped. Preserve its result directory and logs. The earlier afeaffc panel
also stopped on the same route at its 30-minute limit.

`resume_queue.py` is a new controller for the existing v2 manifests and
`run_case.py`. It preserves successful cases, records the one known timeout
as resource-limited, and refuses every other prior result that is incomplete
or ambiguous. It runs one new case at a time and stops on any new failure.
This does not make the one-core 3D t-SNE result complete; that performance
problem requires separate diagnosis or a new algorithm version.

Before launch, verify that no other Mac scientific job is running, the
four-core mass41 3D t-SNE standalone diagnostic has reached a terminal
state, swap/disk pressure are acceptable, and the v2 source and manifests
still match their recorded identities. Then run `--dry-run` against the v2
panel root. A successful dry run must show exactly one `resource_limited`
case and no ambiguous result. Run the controller only after that review.
All output remains under `/Users/silvanopiazza/Documents/Stefano`.

The controller does not change the package source, method parameters, or
case runner, so any resumed scientific case keeps its v2 source identity.
Its queue events are recorded separately in `queue-status-v3.jsonl`; v2
evidence is untouched. Publication results still require a full independent
audit and should not mix package source versions.
