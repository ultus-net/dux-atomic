# RSI experiment ledger

Structured, create-only record of every base-loop attempt, accepted or
rejected. One record per iteration; append only. Never edit or delete a prior
record: a negative result is data, not clutter.

## Schema (one block per iteration)

```text
n · date (UTC) · hypothesis (falsifiable) · trace evidence · code change ·
commit SHA + git tree · artifact name + checksum · exact command/config ·
test results · eval job path · score · gains · losses · exceptions ·
token/cost/duration · interpretation · keep/revert · next hypothesis
```

Schema v2 adds two fields, required on every new record:

```text
selection score (n items) · held-out score (n items, never used for selection)
· prev-chain: sha256:<hex of the preceding record block>
```

`selection score` is the score on the items the loop selected against.
`held-out score` is the score on a disjoint item set never used for
selection. Report both (winner's curse). `prev-chain` links each record to
the sha256 of the prior record block so the create-only rule is
tamper-evident (hash-chained admission).

## Rules

- Append only. One block per iteration. No rewrites, renumbering, or deletes.
- Report `selection score` and `held-out score` side by side; a `keep`
  requires a non-empty `held-out score`. Held-out items are never reused for
  selection.
- `prev-chain` is the sha256 of the preceding record block.
- Record failures with the same care as successes; an empty failures column
  is a smell, not a clean run.
- Name idiosyncratic infrastructure/verifier constraints explicitly, so a
  later reader does not re-derive them.
- Every `keep` cites the eval run that justified it; every `revert` keeps the
  failure evidence and the next hypothesis.
- A record is written by the base loop, not a subagent.

## Records

<!-- append blocks below this line, newest last -->

### n=0 · 2026-11-14 · ledger genesis

- hypothesis (falsifiable): none. This block starts the hash chain, because `~/.config/opencode/lib/validate-ledger.cjs` requires every new record to carry a `prev-chain` equal to the sha256 of a preceding block, and this repository carried no ledger at `cdc580d`.
- trace evidence: `docs/agents/ledger.md` did not exist at `cdc580d`; the scaffold was copied from `~/.config/opencode/templates/rsi/ledger.md` and its record section was empty.
- code change: none. This is a bookkeeping block.
- commit SHA + git tree: the scaffold commit on `docs/82-tooling-inventory`; the sha is recorded in n=1, because a block cannot cite the commit it ships in.
- artifact name + checksum: none.
- exact command/config: none.
- test results: `node ~/.config/opencode/lib/validate-ledger.cjs` at this commit reports one error, `n=0: no preceding record to chain (prev-chain cannot be verified)`. That error is structural: the gate's `checkRecord` requires `prevRecord`, so no genesis block can satisfy it. Records from n=1 on are verified by the gate.
- eval job path: none.
- score: not applicable.
- gains: the chain has a first link, so every later record is verifiable.
- losses: the genesis link is checked by inspection, not by the gate.
- exceptions/idiosyncratic constraints: `prev-chain` here is the sha256 of the empty string (`e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`), which is the conventional empty-input digest and not the hash of a record block.
- token/cost/duration: none.
- interpretation: a tamper-evident chain needs a seed, and the seed is the one link no automated gate can check.
- keep/revert: n/a. Scaffolding, not a candidate; nothing to keep or revert.
- next hypothesis: none.

