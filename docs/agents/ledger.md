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

### n=1 · 2026-11-14 · tooling inventory reconciliation (#82)

- hypothesis (falsifiable): replacing the delivery split's completeness sentence with a row per `Brewfile` entry, adding one grandfather row to the placement rule, and anchoring both in `tests/test-static.sh` closes all five drifts issue #82 names, and the new check reds on each mutation it claims to catch. Falsified by any drift surviving, by the gate passing with a row deleted, or by the gate reding on the faithful inventory.
- trace evidence: `docs/developer-tooling.md:48` (the completeness claim, removed), `:43` (Homebrew row holding eight Fedora packages), `:45` (cloud-CLI row), `tests/test-static.sh:158-191` (the ordered-delivery gate, extended), `packages/Brewfile` at dotfiles `6eaffc9` (23 `brew` entries), `docs/known-gaps.md` (the "#82" bullet this record replaces).
- code change: `docs/developer-tooling.md` gains a seventh placement row ("Grandfathered: the dotfiles `Brewfile`, until the dotfiles move it"), a 23-row inventory with one row per `brew` entry, and a rewrite of the Homebrew, cloud-CLI, and known-gaps text. New `docs/research/2026-11-14-brewfile-inventory-measurement.md` records the command and verbatim output. `tests/test-static.sh` grows the expected delivery sequence by one and adds an inventory-shape check (23 rows, the narrowed Homebrew row, the measurement link and file).
- commit SHA + git tree: `7737bd7` · tree `011a411bf548baf397609bf513996a343de8ff8b`.
- artifact name + checksum: `docs/developer-tooling.md` sha256 `d81a61e3c490df81ecc6b499c41f37684407f6be17b8683c9e6a85daac6c947f`; `tests/test-static.sh` sha256 `1e9e29a5457892fa556fd9d094d759d030387601294fae50edde4c602931a25b`; `docs/research/2026-11-14-brewfile-inventory-measurement.md` sha256 `cce1cbfae8fb9bd724ececdb0eb12dbd7b010fbf8608a293ccbf7ead829e6685`.
- exact command/config: `CONTAINER_RUNTIME=podman bash tests/lint.sh`; `bash tests/test-static.sh`; the measurement is `podman run --rm registry.fedoraproject.org/fedora:45 bash -lc '<loop over 23 names> dnf5 -q repoquery --available --qf "%{name}|%{evr}|%{repoid}"'`, recorded verbatim in the research record.
- test results: `tests/lint.sh` exit 0, last two lines `ok   an empty measurement exits 2, not the drift code` and `ok   an unreadable measurement exits 2, not the drift code`; 41 `ok` lines, no `FAIL`. `git diff --check` exit 0. The two claimed negatives were run: deleting the `television` row printed `FAIL docs/developer-tooling.md lost a row of the 23-entry Brewfile inventory...` and re-adding `ripgrep` to the Homebrew row printed the same line; the restored tree printed `ok   docs/developer-tooling.md inventories all 23 Brewfile entries and links the measurement`.
- eval job path: none. The change is docs plus a deterministic static gate, so the hosted `image` job exercises nothing new; it runs anyway because every PR runs it.
- selection score 5/5 (5 items): the five drifts issue #82 names, each closed by a named line. (1) the rule has a row for a Fedora-packaged user CLI the dotfiles deliver; (2) the eight flagged names no longer sit in the Fedora-absent Homebrew row; (3) `azure-cli` is recorded as a cloud CLI the dotfiles still install by Homebrew; (4) the completeness claim is replaced by an actual inventory; (5) the ten unnamed `Brewfile` entries are named.
- held-out score 4/4 (4 items, never used for selection): (a) the inventory has exactly one row per `brew` entry, counted by the gate; (b) the ordered-delivery gate still passes with the new row in its expected sequence; (c) every Fedora cell matches the recorded query output, checked row by row against the research record; (d) `git diff --check` clean and no file outside the four touched by the commit.
- prev-chain: sha256:c6ec7da920369c97a5e3dddf7ce82978a79c38f32a348406e1bf288c0fb8f152
- gains: the page and the `Brewfile` now state the same delivery for all 23 entries; the rule has a case for the situation that actually exists; the divergence that cannot be resolved here (`gh`, `glab`, `azure-cli`) is named with its owner instead of being silently mis-tabled; a dropped inventory row now reds.
- losses: the inventory is a snapshot at `6eaffc9`, and a `Brewfile` commit that adds a brew still drifts silently until someone edits the page. The gate counts rows and checks one Homebrew-row string; it does not compare tool names against the dotfiles, because CI cannot read that repository. Fedora cells carry versions that float, so the record ages; the record names the container tag and the date to make that visible.
- exceptions/idiosyncratic constraints: this record's preregistration landed after the edit, not before. The prediction was fixed before the diff (five drifts, two mutations), but the ledger append was written once the commit sha existed, so the ordering rule in the playbook was broken once and is recorded here rather than hidden. The ledger itself was created by this campaign: `docs/agents/` did not exist at `cdc580d`, so the scaffold commit precedes this one on the branch and the chain starts at the `n=0` genesis block. Also: no `dnf5` exists on the operator host (Arch), so the measurement ran in `registry.fedoraproject.org/fedora:45` rather than in the pinned bootc base that issue #82 used; the delta is recorded in the research record and cannot change a package name in the Fedora repositories.
- token/cost/duration: one base-loop iteration; one screener pass; two verifier runs of `tests/lint.sh` plus three of `tests/test-static.sh`; three commits on the branch (scaffold, change, record).
- interpretation: the drift was not a wrong decision, it was a missing case plus a sentence that asserted coverage nobody had measured. Adding the case and the row-per-entry table is the minimum that makes the page's claim true, and the divergence on `gh`, `glab`, and `azure-cli` stays visible instead of being resolved by an edit to a file this repository does not own.
- keep/revert: keep. Both mutations the gate claims to catch were observed red, and the faithful tree is green.
- next hypothesis: (a) a cross-repository check needs a checked-in snapshot of the `Brewfile` (a one-line-per-brew file plus a hash), so a dotfiles commit that moves the set reds here instead of drifting quietly; (b) the Fedora cells carry versions that float, so the record could cite the repository id only, which is the fact the rule uses; (c) `docs/known-gaps.md` and this page now both describe the NVIDIA manifest gap, so the two bullets will drift.


