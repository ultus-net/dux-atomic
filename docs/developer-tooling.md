# Developer and sysadmin tooling

The image serves a machine that is a sysadmin's first and a developer's second. That ordering decides who owns each tool: the image ships what has to work on a broken machine and what needs root, and the user-space layers arrive later.

## How a new tool is placed

Apply these tests in order and deliver the tool by the first one that matches. The order is the policy: a later row never overrides an earlier one.

| Test | Delivery | Why this layer |
| --- | --- | --- |
| Needs root, a kernel capability, or early boot | Image | Nothing else exists before the boot finishes. `tcpdump` and `strace` are examples |
| Fedora packages it and the image needs it: before the first login, on a broken machine, or at the version the build and tests use | Image, recorded in the lock | Fedora signs it and the lock pins the NEVRA. The image may also assert it at runtime |
| A cloud or operations CLI | A pinned `podman` container | Digest-pinned, no host mutation, and its own cadence. See [the agent container](agent-container.md) for the isolation rules |
| A GUI application | Flathub | Sandboxed, updated by its publisher, no host package licence burden |
| User-level CLI that Fedora does not package | Homebrew, from the dotfiles `Brewfile` | No root and one prefix, and the alternative is nothing. Check with `dnf5 repoquery --available <name>` before choosing it |
| User-level CLI that Fedora packages and the dotfiles already deliver | Grandfathered: the dotfiles `Brewfile`, until the dotfiles move it | The `Brewfile` is the pin, the tool has no boot dependency, and moving it is a dotfiles change under the #70 hand-off. The row exists so the inventory can record the divergence instead of implying Fedora owns the tool. The cloud-CLI row above already claims `gh`, `glab`, and `azure-cli`, so this row never places them |
| A language-specific developer tool for one project | That project's devcontainer or a Distrobox | The project owns its runtime version |

A tool that Fedora packages and that the image does not need before login never enters the image. It goes to the grandfather row while the dotfiles still deliver it, and to a container or a Flatpak once they stop.

## Homebrew is the fallback, not the default

Homebrew is the right answer for two rows above: user-level CLI that Fedora does not package, and the grandfather row where the dotfiles already deliver a tool Fedora does package. Its own documentation scopes it that way, under Features: the first listed use is "Install software not packaged by your host distribution".

It is also not a supported configuration on this base, and that is a reason to keep it narrow. Homebrew's support tiers list Linux Tier 1 as "Ubuntu within its standard support window or a Homebrew-provided Docker image", with a `glibc` at or above 2.39 and the default prefix. Fedora appears in no tier, so a Fedora-only bug sits outside the project's support contract even though the same page gives Fedora bootstrap commands. Never place a Homebrew package on a path the boot needs.

The trust model differs from Fedora's, which is why the pin lives in the dotfiles: "Homebrew does not use any libraries provided by your host system, except *glibc* and *gcc* if they are new enough", and it "expects a working system C compiler and the standard Linux development tools". The `Brewfile` records intent, not a digest, and nothing signs a Homebrew package. The pinned source for a Homebrew tool is therefore the dotfiles commit that names it.

Homebrew runs on the host, not in a container, because the dotfiles own the `Brewfile` and the image already ships the compiler Homebrew bootstraps against. [The research record](research/2026-11-14-package-delivery-layers.md) lists containerized Homebrew as a bootstrap option that this policy rejected, so it is not a live alternative. Reopening it is a policy change, not a tool addition.

Sources: [Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux), [Support Tiers](https://docs.brew.sh/Support-Tiers). The evidence for every row, and what each project says about its own layer, is in [the package-delivery research record](research/2026-11-14-package-delivery-layers.md).

## Delivery split

The table below is the result of applying the tests above, not a second policy.

| Tool | Source | Reason |
| --- | --- | --- |
| `gcc`, `gcc-c++`, `make`, `patch`, `zlib-ng-compat-devel`, `bzip2-devel` | Image | Homebrew on Linux states that it expects a working system C compiler and the standard Linux development tools, and that its own GCC "does not replace the system compiler required for bootstrap and post-install steps". Its Fedora instructions are `dnf group install development-tools` plus `procps-ng`, `curl`, and `file`. The base carries no compiler, so the image ships that toolchain |
| `nodejs` 22.23.1, `nodejs-npm` 10.9.8 | Image | `install/20-tools.sh` in the [dotfiles repository](https://github.com/ultus-net/dotfiles) installs its npm globals only when `npm` exists, and `opencode-ai` and `pnpm` are two of them. Fedora splits npm out of the `nodejs` package, so both names are needed |
| `btop`, `tmux`, `htop`, `git`, `just`, `fzf`, `distrobox`, `wl-clipboard`, `rsync`, `zip` | Image | Terminal tools that must exist before any user-space package manager does |
| `lsof`, `strace`, `tcpdump`, `nmap`, `nmap-ncat`, `mtr`, `tree`, `ncdu`, `wget2`, `smartmontools`, `lm_sensors`, `pciutils`, `usbutils`, `dmidecode`, `sysstat`, `7zip` | Image | Diagnostics and hardware inspection. A machine with a broken network or a failing disk needs these before Homebrew, Flatpak, or a container exists |
| `podman`, `skopeo`, `python3`, `openssh-clients`, `jq`, `curl`, `unzip`, `bind-utils`, `socat` | Base image | Inherited from `fedora-bootc:45` and asserted by the manifest-wide `rpm -q --whatprovides` check |
| `fd`, `starship`, `go` (Fedora's `golang`) | Homebrew, through the dotfiles `Brewfile` | The approved design reuses the dotfiles copies (`docs/superpowers/specs/2026-11-09-dux-atomic-design.md`, "Reuse existing atuin, starship, zoxide, fd, ripgrep"), and Fedora 45 carries none of these three names: `fd` and `go` answer only as `fd-find` and `golang`, which are different packages |
| `atuin`, `bash-preexec`, `chezmoi`, `direnv`, `git-credential-oauth`, `rclone`, `ripgrep`, `restic`, `shellcheck`, `stress-ng`, `ugrep`, `yq`, `zoxide`, `charmbracelet/tap/crush` | Homebrew, through the dotfiles `Brewfile`, grandfathered | Fedora 45 packages all but `crush`, and the `Brewfile` installs every one of them. The placement rule gains the grandfather row above rather than moving fourteen tools the dotfiles own (#82) |
| `gh`, `glab`, `azure-cli` | Homebrew today, while the cloud-CLI row assigns a pinned container | Fedora 45 packages all three. The rule claims them for the container row, the dotfiles still install them by Homebrew, and the divergence is recorded here rather than resolved: the `Brewfile` is the dotfiles' file (#70) |
| `lazygit`, `yazi` | Homebrew, through the dotfiles | Proposed by the design spec, but Fedora 45 carries neither and the dotfiles `Brewfile` does not list them yet |
| `kubectl`, `helm`, `OpenTofu`, cloud CLIs, `k9s`, `stern`, `kubectx` | A pinned operations container, run with `podman` | The design keeps the host image free of cloud SDKs and gives them their own update cadence |
| Zed, Bitwarden, Obsidian, Zen Browser, Discord, Spotify | Flathub at first login | User GUI applications, recorded in [Applications](applications.md) |

This table names the tools whose delivery the policy decides. The inventory below
names every `brew` entry the dotfiles install, so a tool cannot be added to one
and left out of the other without a reader noticing.

## The inventory the dotfiles install

`packages/Brewfile` in the [dotfiles repository](https://github.com/ultus-net/dotfiles)
carries 23 `brew` entries at commit `6eaffc9`. Every one is below, with the
`Brewfile` line and the Fedora measurement that decides its row. The commands and
their verbatim output are in [the inventory measurement](research/2026-11-14-brewfile-inventory-measurement.md).

| Tool | `Brewfile` | Fedora 45 | Delivered by |
| --- | --- | --- | --- |
| `atuin` | `:4` | `atuin` 18.12.1-4.fc45 | Homebrew, grandfathered |
| `azure-cli` | `:6` | `azure-cli` 2.88.0-2.fc45 | Homebrew today; the cloud-CLI row assigns a container |
| `bash-preexec` | `:8` | `bash-preexec` 0.6.0-1.fc45 | Homebrew, grandfathered |
| `chezmoi` | `:10` | `chezmoi` 2.72.0-1.fc45 | Homebrew, grandfathered |
| `direnv` | `:12` | `direnv` 2.37.1-7.fc45 | Homebrew, grandfathered |
| `dysk` | `:14` | absent | Homebrew, the row the rule grants it |
| `fd` | `:16` | absent as `fd`; `fd-find` 10.4.2-6.fc45 is a different package | Homebrew, the row the rule grants it |
| `gh` | `:18` | `gh` 2.97.0-1.fc45 | Homebrew today; the cloud-CLI row assigns a container |
| `git-credential-oauth` | `:20` | `git-credential-oauth` 0.17.2-5.fc45 | Homebrew, grandfathered |
| `glab` | `:22` | `glab` 1.112.0-1.fc45 | Homebrew today; the cloud-CLI row assigns a container |
| `go` | `:24` | absent as `go`; `golang` 1.27.1-2.fc45 is a different package | Homebrew, the row the rule grants it |
| `rclone` | `:26` | `rclone` 1.75.0-2.fc45 | Homebrew, grandfathered. It syncs files to cloud storage but carries no cloud SDK, so the cloud-CLI row does not claim it |
| `ripgrep` | `:28` | `ripgrep` 15.2.0-1.fc45 | Homebrew, grandfathered |
| `restic` | `:30` | `restic` 0.19.1-1.fc45 | Homebrew, grandfathered; `backup.timer` in the dotfiles runs it as the user |
| `shellcheck` | `:32` | `ShellCheck` 0.11.0-5.fc45, binary `/usr/bin/shellcheck` | Homebrew, grandfathered |
| `starship` | `:34` | absent | Homebrew, the row the rule grants it |
| `stress-ng` | `:36` | `stress-ng` 0.22.01-1.fc45 | Homebrew, grandfathered |
| `tealdeer` | `:38` | absent | Homebrew, the row the rule grants it |
| `television` | `:40` | absent | Homebrew, the row the rule grants it |
| `ugrep` | `:42` | `ugrep` 7.8.2-2.fc45 | Homebrew, grandfathered |
| `yq` | `:44` | `yq` 4.53.3-2.fc45 | Homebrew, grandfathered |
| `zoxide` | `:46` | `zoxide` 0.9.8-3.fc45 | Homebrew, grandfathered |
| `charmbracelet/tap/crush` | `:48` | no Fedora package; a third-party tap | Homebrew, through the tap it names |

Sixteen of the 23 are Fedora packages, which is why the grandfather row exists:
the rule had no row for a Fedora-packaged tool the image does not need before
login. Six are not, so the Homebrew fallback row keeps them. The twenty-third,
`crush`, resolves in neither set.

The same `Brewfile` also installs one cask (`git-credential-manager`, `:49`),
seven `npm` globals (`:79` through `:85`), and 29 `flatpak` entries (`:50`
through `:78`). Those are three other layers. The cask is a user binary with no
`brew` formula, the npm entries are the language-package-manager layer that the
dotfiles own, and the Flatpaks are the Flathub row. The inventory above is the
`brew` layer, which is the one this page's Homebrew rows decide.

## What the split buys

Everything the tests above keep out of the image updates on its own cadence. Homebrew packages update without an image rebuild, a Flatpak app updates when its publisher ships, and an operations container carries the cloud CLIs that would otherwise pin `kubectl` to the OS release. The split keeps the image small and keeps a routine tool upgrade out of a deployment.

## Verification

`tests/verify-image.sh` covers the layer in three ways. The manifest-wide `rpm -q --whatprovides` call proves every package name resolves in the built image. A Node check runs `node --version` and requires 22.18 or newer, because that is where the dotfiles get default TypeScript type stripping. A second check runs `npm --version` and fails when the npm package is missing, which is the failure that would silence every dotfiles npm global. `tests/test-static.sh` reds when either probe, the 22.18 floor, or either manifest name leaves the repository, so a later edit cannot drop the contract quietly.

`manifests/packages-common.lock` records the Fedora NEVRA of each new name. Fedora lines float with the updates repository, so the lock is a record rather than a drift gate for them, as [Build](build.md) explains.

`tests/test-static.sh` also anchors this page. It compares the ordered delivery paths in the placement table against the expected sequence, so a reorder, a removal, or a reworded path reds, and it reds when the `dnf5` check, the support-tier boundary, or the research record this page links disappears. It is a presence and order check, not a reading of the policy's meaning.

## Known gaps

- The inventory is reconciled with the dotfiles `Brewfile` at `6eaffc9`, and the reconciliation is a recorded divergence rather than a move (#82, closed by this page). Sixteen of the 23 `brew` entries are Fedora 45 packages, so the placement table gains a grandfather row that names the dotfiles `Brewfile` as their delivery until the dotfiles move them. `gh`, `glab`, and `azure-cli` are cloud CLIs, so the earlier cloud-CLI row claims them while the dotfiles still install them by Homebrew. Moving any of them is a `Brewfile` change in the dotfiles repository under the #70 hand-off. The measurement that decides each row is [the inventory measurement](research/2026-11-14-brewfile-inventory-measurement.md).
- `lazygit` and `yazi` are not in the Fedora 45 repositories, so no image test covers them. The dotfiles `Brewfile` is the intended delivery path and does not list them yet.
- The image ships a compiler and its headers but no `cmake` or `meson`. A native build needs those from Homebrew or a Distrobox container.
- The inventory has no automated check yet. Nothing compares the dotfiles `Brewfile` against the table above, so a tool added to one and not the other drifts without a red gate. The `Brewfile` commit is also the only pin, because nothing signs a Homebrew package.
- No test runs a Homebrew tool, a Flatpak application, or an operations container on a built image. The placement rule is enforced by a static check on this page, not by exercising the layers.
- No test launches an interactive session as the operator and runs a tool. The checks above prove the packages exist and the two runtimes execute.
- The dotfiles stage 20 is not recorded as running on a booted image yet. Its disk build and VM boot need rootful podman, which the agent sessions cannot run, so [the bootstrap hand-off](research/2026-11-14-dotfiles-bootstrap.md) records the blocked commands and the exact operator sequence that finishes the proof. `tests/vm/boot-smoke.sh` carries an opt-in `POST_LOGIN_CMD` hook to capture that run (#70).
- Project-scoped rootless agent containers are not exercised by the image tests here. [The agent container page](agent-container.md) documents the profile and how to run it (#71).
