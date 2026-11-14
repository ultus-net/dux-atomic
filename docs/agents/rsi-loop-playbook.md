# RSI loop playbook

The operating manual for the `/rsi-loop` and `/rsi-campaign` commands, and the
repo-local grounding those commands read first.

## Before the first iteration

The loop depends on three artifacts in this repo. Create any missing one from
`~/.config/opencode/templates/rsi/` before running an iteration:

- `docs/agents/rsi-loop-playbook.md` — this file.
- `docs/agents/ledger.md` — the create-only experiment ledger.
- `docs/agents/lessons.md` and `docs/agents/lessons/` — the lesson memory.

`docs/agents/reading-list.md` holds the compaction corpus. This repository does
not carry one: the campaign brief names each mechanism with its arXiv id, and a
ledger record cites that pair rather than a local file. Add the file here when
the corpus is vendored, and point the records at it.

## The base loop

One iteration maps to one branch and one PR:

1. **PROPOSE** — pick one minimal candidate change. Read the actual code first;
   cite the files you read in the proposal.
2. **PREDICT** — before editing, register a falsifiable claim: expected effect
   on the metric, how it will be verified, and at-risk regressions.
3. **IMPLEMENT** — delegate mechanical work to an `executor` subagent with a
   full spec (inputs, constraints, acceptance command). Keep the diff minimal.
   Start on the cheap tier; escalate only on an observable trigger.
4. **EVALUATE** — run the external verifier only; self-review is not evidence.
   Change one causal axis per iteration.
5. **SELECT** — regularize selection: anneal the edit budget, screen proposals
   for benchmark-specific trickery, prune stale or too-small edits, and advance
   the incumbent only on a minimum effect size. Delegate a fresh-eyes check to
   a `reviewer` subagent. Archive rejected attempts with their failure evidence.
6. **REMEMBER** — write one lesson file under `docs/agents/lessons/`, and append
   one structured record to `docs/agents/ledger.md`. Write it either way; a
   negative result is data.

## Hard rules

- Never edit tests, the verifier, baselines, or run logs to make a change pass.
- Live settings changes go through a sanctioned installer, never a direct edit.
- A negative result is a valid result: log it and stop.

## Multi-iteration campaigns

`/rsi-loop` runs one iteration. `/rsi-campaign` runs a bounded batch (3-5
iterations) in one session with explicit stop brakes and subagent fan-out: it
builds a diversity-tagged candidate set before iterating, enforces no-gain and
same-type stop brakes, and isolates overlapping edits in git worktrees. Each
iteration still maps to one branch and one PR.

## Anchors

- **verifier** — `CONTAINER_RUNTIME=podman bash tests/lint.sh`. It runs
  `bash -n`, shellcheck, hadolint, actionlint, then `tests/test-static.sh`,
  `tests/test-agent-container.sh`, and `tests/test-lock-drift.sh`. The hosted
  `image` job is the second verifier and costs 17 to 21 minutes.
- **metric** — count of red gates and unproven claims closed, per iteration.
  The noise floor is zero for the deterministic gates: a static check either
  reds on the mutation or it does not, so this loop records a deterministic
  verifier and skips the matched-budget test-time-scaling control that a
  model-scored verifier would require. The hosted `image` job is the noisy one,
  because a boot can fail on runner timing rather than on the diff.
- **frozen ruler** — `tests/test-static.sh` at the merge base of the branch, plus
  `tests/verify-image.sh` for anything that reaches a built image. A change may
  add checks to the suite. A change may not relax one.

## Repo-specific brakes

- `main` is protected: every change lands through a branch and a PR, and branch
  protection wants an up-to-date head, so merging one PR re-runs every open
  one's `image` job. Merge one at a time.
- Work items that need hardware (a game launch on the gaming machine, a Secure
  Boot boot on either target, an NVIDIA boot) are not candidates. A candidate
  whose evidence needs a machine this session cannot reach is dropped at
  appraisal, not attempted.
- `docs/agents/lessons.md` and this file are campaign infrastructure. A change
  to them is a scaffold commit, declared as such, never a candidate.
