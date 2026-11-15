# Lessons — append-only agent memory

Itemized, id'd, evidence-backed bullets (ACE-style). Append only — never
rewrite, renumber, or delete existing bullets. Dedupe by listing ids in a
DEDUPE note for a later pass; a human or a dedicated consolidation pass does
the merging.

Admission gate: accumulation is non-monotonic and a defective lesson
contaminates later ones irreversibly, so a candidate lesson must pass an
external critical check — does the cited evidence actually support the
claim? — *before* it is written here. Post-hoc dedupe clears clutter; it
cannot undo contamination. The semantic half — evidence actually supports the
claim — remains an external review, not a regex.

## Format

- L<nnn> — <one-line lesson> (evidence: <file, run, or PR reference>)

One file per lesson under `lessons/`, named `<timestamp>-<slug>.md`, each
carrying its id in the bullet and registered below.

## Registry

<!-- register lesson files below this line, newest last -->

- L001 — a completeness claim over an external list is a claim about a diff; name the list, its commit, and one row per entry, or drop the claim (evidence: `docs/developer-tooling.md:48` before `7737bd7`, `docs/agents/lessons/20261114T054500Z-completeness-claim-needs-a-diff.md`)

- L002 — a package name that promises a property (`-matched`, `-latest`, `uname-r`) states its own version relation, not a lookup on the machine; read `rpm -qR` and assert the property at build time (evidence: `rpm -qR kernel-devel-matched` in the `aae9510831b0` image, `3500e54`, `docs/agents/lessons/20261114T062000Z-name-promising-a-property-is-not-a-check.md`)

- L004 — a substring grep is not a gate check: anchor the pattern on a character a rename cannot keep (the closing parenthesis, the flag list) and prove the negative with the edit a maintainer would make, not by deleting the file (evidence: the rename probe on `grep -qF 'dnf5 --dump-main-config'` in `tests/test-static.sh` printed `ok` and exit 0, `docs/agents/lessons/20261115T085146Z-a-substring-grep-is-not-a-gate-check.md`)

- L005 — assert the whole line, not a fragment: a comment, a second call site, or a rename that keeps the fragment satisfies a substring match, so anchor both ends with `grep -qxF` over the line itself (evidence: reviewer P1 on the `grep -qF` form that kept only the command prefix, the committed `grep -qxF "$dnf_readback"`, `docs/agents/lessons/20261115T091500Z-assert-the-whole-line-not-a-fragment.md`)

- L006 — a conflict resolution is a deletion until the diff says otherwise: a merge that keeps one side of a conflicted file removes the other side's lines, so read `git show --stat` on the conflicted paths and compare each parent's line count (evidence: `b3bb525` deleted 95 lines of `CHANGELOG.md`, 100 lines at `b3a2f8f` to 6 at the merge, and the `static` run at `b3bb525` concluded `success`, `docs/agents/lessons/20261115T090646Z-a-conflict-resolution-is-a-deletion.md`)

- L007 — a closing keyword in code formatting does not close the issue: the forge reads the rendered body, so `Fixes #123` in backticks leaves the work item open, and the check is the issue's state after the merge (evidence: PR #124 merged 2026-11-15T06:31:51Z, `#123` closed by hand at 2026-11-15T08:39:21Z, `docs/agents/lessons/20261115T090646Z-a-closing-keyword-in-code-formatting-does-not-close.md`)

- L008 — a green single script is not a green suite: before calling a gate bypassable, run the command CI runs and read its order, because a false green in a later step is unreachable when an earlier step rejects the input (evidence: `bash tests/test-static.sh` exit 0 on a workflow `tests/lint.sh` rejects with `.github/workflows/ci.yml:275:0: could not parse as YAML`, `docs/agents/lessons/20261115T093500Z-a-green-single-script-is-not-a-green-suite.md`)

