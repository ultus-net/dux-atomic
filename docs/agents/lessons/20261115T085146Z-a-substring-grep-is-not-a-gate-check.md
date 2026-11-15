# L004 — a substring grep is not a gate check

**Claim.** A static assertion that greps for a command's prefix passes when a
future editor renames the command, because the replacement still contains the
prefix. Anchor the search on a character that cannot survive a rename — the
closing parenthesis, the flag list, the full line — and prove the negative by
making the edit a maintainer would actually make, not by deleting the file.

**Applicability conditions.** Applies to every `grep -qF` assertion over a
script, a workflow, or a config that names a command. Does not apply to an
assertion over a whole file's presence, or to a pattern already anchored at both
ends (`grep -qx`).

**Evidence.** Iteration 1 of the 2026-11-15 campaign added
`grep -qF 'dnf5 --dump-main-config'` to `tests/test-static.sh` as the check that
`tests/verify-image.sh` still reads the dnf.conf values back. The negative proof
renamed the flag to `--dump-main-config-removed`, and the check printed
`ok   the overlay ships the dnf.conf defaults and the verifier reads them back`
with exit 0: the substring matched the renamed command. Anchoring the pattern
on the closing parenthesis (`dnf5 --dump-main-config)`) and repeating the same
rename printed
`FAIL tests/verify-image.sh no longer reads the dnf.conf values back with dnf5 --dump-main-config`
with exit 1. The first negative was a false green, and only running it found
that.

**What this lesson does not license.** It does not say every grep needs a
regex. It says the negative proof must be the edit that preserves meaning for a
careless reader, and that a passing negative is evidence about the check, not
about the code.
