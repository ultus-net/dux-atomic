# L008 — a green single script is not a green suite

**Claim.** A test script's own exit status says nothing about what CI concludes
when a later step runs it. Before calling a gap a defect, run the command CI
runs, and read the order inside it. A false green in step 4 is unreachable when
step 2 already rejects the input, and reporting it as a hole spends a whole
iteration on a gate that cannot be bypassed.

**Applicability conditions.** Applies to any assertion about whether a gate can
be bypassed, in a suite that runs several checks in sequence. Does not apply when
the script under discussion is itself the CI entry point, where its exit status
is the suite's.

**Evidence.** Iteration 3 of the 2026-11-15 campaign tested a review follow-up
that claimed the awk job-block extractor in `tests/test-static.sh` could be
truncated by a two-space mapping inside a job. The claim reproduced in
isolation: with `  note: ...` inserted in the `image-nvidia` job and a second
`tests/verify-image.sh --no-package-lock` after it, `bash tests/test-static.sh`
printed its `ok` line and `static checks passed` with exit 0, counting 1
invocation instead of 2. The composite gate told a different story:
`CONTAINER_RUNTIME=podman bash tests/lint.sh` exited 1 before the static tests
ran, with `.github/workflows/ci.yml:275:0: could not parse as YAML: yaml: line
275: mapping values are not allowed in this context [syntax-check]`. A line at
two spaces closes every open mapping, so it is a sibling key under `jobs:`, not
a mapping inside the job. The extractor's boundary is the YAML boundary, and the
input that defeats it is one that actionlint rejects.

**What this lesson does not license.** It does not say a single script's green is
worthless, or that a suite's early failure excuses a later weakness. It says the
bypass claim must name the entry point that CI runs, and the measurement must be
taken there.
