# L001 — a completeness claim over an external list is a claim about a diff

**Claim.** A page that says it names every tool from another repository's list is
stating an equality between two files, and it goes false on the other repository's
next commit. Name the source list, its commit, and one row per entry, or drop the
claim. A completeness sentence with no generated table beside it is unverified.

**Applicability conditions.** Applies when a document asserts coverage of a list
owned elsewhere (a package list, an inventory, an allowlist, a schema). Does not
apply to a document that only names the tools it itself decides; that page makes
no completeness claim, and adding one would invent a maintenance burden.

**Evidence.** `docs/developer-tooling.md:48` claimed "The dotfiles `Brewfile`
holds the full set and carries more entries than this table" while the page named
ten of that `Brewfile`'s 23 `brew` entries nowhere (`chezmoi`, `direnv`,
`shellcheck`, `tealdeer`, `ugrep`, `television`, `dysk`, `stress-ng`,
`git-credential-oauth`, `charmbracelet/tap/crush`). The page was written from the
design spec, not from the `Brewfile`. Three separate drifts were invisible for the
same reason: eight Fedora-packaged names sat in a Homebrew row that grants only
Fedora-absent tools, `azure-cli` was Homebrew while the rule put cloud CLIs in a
container, and the rule had no row for the case the eight names actually were.
Commit `7737bd7` replaces the sentence with a 23-row table, one row per `brew`
entry with its `Brewfile` line and its `dnf5 repoquery --available` result, and
`tests/test-static.sh` now reds when a row disappears or when the Homebrew row
widens.

**What this lesson does not license.** Copying the list into the page also copies
its staleness. The table is a snapshot with a named commit (`6eaffc9`), not a
gate; the gate needs the other repository's file, which CI cannot read
(`docs/developer-tooling.md`, Known gaps).
