# Brewfile inventory measurement (issue #82)

Commands run on 2026-11-14 on the operator host, with verbatim output. This
record is the evidence for every Fedora cell in the inventory of
[developer tooling](../developer-tooling.md), and for the placement decision that
page records.

## What was measured

The 23 `brew` entries in `packages/Brewfile` of the dotfiles repository at commit
`6eaffc9`, against the Fedora 45 repositories.

## Container used, and why it is not the pinned image

The query ran in `registry.fedoraproject.org/fedora:45`, not in the pinned
`quay.io/fedora/fedora-bootc:45` image that `Containerfile` builds from. The
question is which names the Fedora repositories carry, and both containers enable
the same Fedora release and updates repositories. The pinned base additionally
enables the duxlabs COPRs and the negativo17 multimedia repository, which serve
no name in this set, so the answer does not depend on which of the two ran the
query. The container is a tag, not a digest: a later run against a newer Fedora
45 snapshot can legitimately differ in version, never in package name.

## Command

One loop, one name at a time, because `dnf5`'s `--qf` does not append a newline
unless the format string carries one, which concatenated multi-build rows in the
first attempt.

```sh
podman run --rm registry.fedoraproject.org/fedora:45 bash -lc '
  names="atuin azure-cli bash-preexec chezmoi direnv dysk fd gh \
git-credential-oauth glab go rclone ripgrep restic shellcheck starship stress-ng \
tealdeer television ugrep yq zoxide lazygit yazi"
  for n in $names; do
    out=$(dnf5 -q repoquery --available \
      --qf "%{name}|%{evr}|%{repoid}" "$n" 2>/dev/null | head -1)
    if [ -z "$out" ]; then printf "ABSENT  %s\n" "$n"
    else printf "PRESENT %s\n" "$out"; fi
  done'
```

`lazygit` and `yazi` are not `Brewfile` entries. They are included because
`docs/developer-tooling.md` claims both are absent from Fedora, and this run is
where that claim is checked.

## Output

```text
PRESENT atuin|18.12.1-4.fc45|fedora
PRESENT azure-cli|2.88.0-2.fc45|fedora
PRESENT bash-preexec|0.6.0-1.fc45|fedora
PRESENT chezmoi|2.72.0-1.fc45|fedora
PRESENT direnv|2.37.1-7.fc45|fedora
ABSENT  dysk
ABSENT  fd
PRESENT gh|2.97.0-1.fc45|fedora
PRESENT git-credential-oauth|0.17.2-5.fc45|fedora
PRESENT glab|1.112.0-1.fc45|fedora
ABSENT  go
PRESENT rclone|1.75.0-2.fc45|fedora
PRESENT ripgrep|15.2.0-1.fc45|fedora
PRESENT restic|0.19.1-1.fc45|fedora
PRESENT ShellCheck|0.11.0-5.fc45|fedora
ABSENT  starship
PRESENT stress-ng|0.22.01-1.fc45|fedora
ABSENT  tealdeer
ABSENT  television
PRESENT ugrep|7.8.2-2.fc45|fedora
PRESENT yq|4.53.3-2.fc45|fedora
PRESENT zoxide|0.9.8-3.fc45|fedora
ABSENT  lazygit
ABSENT  yazi
```

`ShellCheck` is Fedora's package name for `shellcheck`; the binary it installs is
`/usr/bin/shellcheck`.

Three names the first attempt reported absent are carried under a different
package name. A second run measured the alternatives, because `go` and `fd` each
have a plausible Fedora spelling and a false `ABSENT` would have put a
Fedora-packaged tool in the Homebrew layer for no reason:

```sh
podman run --rm registry.fedoraproject.org/fedora:45 bash -lc '
  for n in golang fd-find bat exa; do
    out=$(dnf5 -q repoquery --available \
      --qf "%{name}|%{evr}|%{repoid}" "$n" 2>/dev/null | head -1)
    if [ -z "$out" ]; then printf "ABSENT  %s\n" "$n"
    else printf "PRESENT %s\n" "$out"; fi
  done'
```

```text
PRESENT golang|1.27.1-2.fc45|fedora
PRESENT fd-find|10.4.2-6.fc45|fedora
PRESENT bat|0.26.1-4.fc45|fedora
ABSENT  exa
```

The last two are controls: a name that should resolve proves the query still
answers after the earlier run, and `exa` is a package Fedora retired, so a
present result there would have meant the query was matching something other than
a package name.

## Findings

- 16 of the 23 `brew` entries are Fedora 45 packages under the name the
  `Brewfile` uses: `atuin`, `azure-cli`, `bash-preexec`, `chezmoi`, `direnv`,
  `gh`, `git-credential-oauth`, `glab`, `rclone`, `ripgrep`, `restic`,
  `shellcheck`, `stress-ng`, `ugrep`, `yq`, `zoxide`.
- 7 are not: `dysk`, `fd`, `go`, `starship`, `tealdeer`, `television`,
  `charmbracelet/tap/crush`. `fd` and `go` resolve under `fd-find` and `golang`,
  which are different packages with different file lists, so the Homebrew entry
  is not redundant with a Fedora one.
- `lazygit` and `yazi` are absent, so the page's claim about both holds on this
  measurement.
- The eight names issue #82 flagged are all confirmed Fedora packages. The
  measurement adds eight more the page does not mention at all: `azure-cli`,
  `bash-preexec`, `chezmoi`, `direnv`, `git-credential-oauth`, `shellcheck`,
  `stress-ng`, `ugrep`.

## What this record does not prove

- That any of these names installs cleanly, or that the Homebrew build and the
  Fedora build behave the same. Only availability is measured.
- Anything about `git-credential-manager` (a cask), the seven `npm` entries, or
  the 29 `flatpak` entries in the same `Brewfile`. They are other layers, and
  this record is about the `brew` layer.
- The Fedora 46 answer. The query is against `fedora:45`.
