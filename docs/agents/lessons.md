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

