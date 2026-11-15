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

