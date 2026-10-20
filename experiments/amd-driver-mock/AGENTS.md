# Driver mock experiment workflow

- HAMi is the first consumer. Keep its source unchanged; implement the required
  ABI and device behavior in this experiment rather than forging allocations.
- Read COMPARISON.md and versions.env before extending an interface. Compare
  both with the pinned original main baseline and the design checkpoint, so
  prior OpenShift work is not miscounted as driver-mock changes.
- For each iteration, update implemented interfaces, unimplemented behavior,
  evidence, and merge-back classification. Keep reusable corrections in narrow
  independent commits with standalone tests. Do not merge main automatically.
- Keep normal quick start and unrelated worktrees unchanged. Use the dedicated
  cluster/kubeconfig and cleanup only its named resources.
- Preserve one profile/state authority. Do not replace the backend with ad-hoc
  testdata, /dev/null aliases, patched HAMi scheduler choices or fabricated node
  registration. ABI unit-test inputs are distinct from the actual integration.
- Record actual logs and pins. Device opens, configured masks and memory limits
  do not establish HIP execution or hardware isolation.
- Every new image needs a build recipe, published version/provenance and docs.
  No external PR or new repository without the user's explicit authorization.
