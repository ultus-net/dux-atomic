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
| A language-specific developer tool for one project | That project's devcontainer or a Distrobox | The project owns its runtime version |

A tool that Fedora packages and that the image does not need before login belongs in a container or a Flatpak, not in the image.

## Homebrew is the fallback, not the default

Homebrew is the right answer for exactly one row above: user-level CLI that Fedora does not package. Its own documentation scopes it that way, under Features: the first listed use is "Install software not packaged by your host distribution".

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
| `fd`, `ripgrep`, `zoxide`, `starship`, `yq`, `gh`, `glab`, `restic`, `rclone`, `atuin`, `go` | Homebrew, through the dotfiles `Brewfile` | The approved design reuses the dotfiles copies (`docs/superpowers/specs/2026-11-09-dux-atomic-design.md`, "Reuse existing atuin, starship, zoxide, fd, ripgrep") |
| `lazygit`, `yazi` | Homebrew, through the dotfiles | Proposed by the design spec, but Fedora 45 carries neither and the dotfiles `Brewfile` does not list them yet |
| `kubectl`, `helm`, `OpenTofu`, cloud CLIs, `k9s`, `stern`, `kubectx` | A pinned operations container, run with `podman` | The design keeps the host image free of cloud SDKs and gives them their own update cadence |
| Zed, Bitwarden, Obsidian, Zen Browser, Discord, Spotify | Flathub at first login | User GUI applications, recorded in [Applications](applications.md) |

This table names the tools whose delivery the policy decides. The dotfiles `Brewfile` holds the full set and carries more entries than this table, so read the table as the decision and the `Brewfile` as the inventory (#82).

## What the split buys

Everything the tests above keep out of the image updates on its own cadence. Homebrew packages update without an image rebuild, a Flatpak app updates when its publisher ships, and an operations container carries the cloud CLIs that would otherwise pin `kubectl` to the OS release. The split keeps the image small and keeps a routine tool upgrade out of a deployment.

## Verification

`tests/verify-image.sh` covers the layer in three ways. The manifest-wide `rpm -q --whatprovides` call proves every package name resolves in the built image. A Node check runs `node --version` and requires 22.18 or newer, because that is where the dotfiles get default TypeScript type stripping. A second check runs `npm --version` and fails when the npm package is missing, which is the failure that would silence every dotfiles npm global. `tests/test-static.sh` reds when either probe, the 22.18 floor, or either manifest name leaves the repository, so a later edit cannot drop the contract quietly.

`manifests/packages-common.lock` records the Fedora NEVRA of each new name. Fedora lines float with the updates repository, so the lock is a record rather than a drift gate for them, as [Build](build.md) explains.

`tests/test-static.sh` also anchors this page. It compares the ordered delivery paths in the placement table against the expected sequence, so a reorder, a removal, or a reworded path reds, and it reds when the `dnf5` check, the support-tier boundary, or the research record this page links disappears. It is a presence and order check, not a reading of the policy's meaning.

## Known gaps

- The inventory predates the rule in one place. Eight names in the Homebrew row are Fedora 45 packages, measured with `dnf5 repoquery --available` in the pinned base on 2026-11-14: `ripgrep`, `zoxide`, `yq`, `gh`, `glab`, `restic`, `rclone`, `atuin`. The rule gives a Fedora-packaged interactive CLI no row, because the image does not need it before login and it is not a cloud CLI, so those eight sit in a layer the rule does not grant them. The dotfiles also install `azure-cli` by Homebrew while the inventory puts cloud CLIs in a container. Reconciling the two is [#82](https://github.com/ultus-net/dux-atomic/issues/82), and a dotfiles edit belongs to that repository under the #70 hand-off.
- `lazygit` and `yazi` are not in the Fedora 45 repositories, so no image test covers them. The dotfiles `Brewfile` is the intended delivery path and does not list them yet.
- The image ships a compiler and its headers but no `cmake` or `meson`. A native build needs those from Homebrew or a Distrobox container.
- The Homebrew row has no automated check yet. Nothing compares the dotfiles `Brewfile` against this page, so a tool added to one and not the other drifts without a red gate. The `Brewfile` commit is also the only pin, because nothing signs a Homebrew package.
- No test runs a Homebrew tool, a Flatpak application, or an operations container on a built image. The placement rule is enforced by a static check on this page, not by exercising the layers.
- No test launches an interactive session as the operator and runs a tool. The checks above prove the packages exist and the two runtimes execute.
- The dotfiles stage 20 is not recorded as running on a booted image yet. Its disk build and VM boot need rootful podman, which the agent sessions cannot run, so [the bootstrap hand-off](research/2026-11-14-dotfiles-bootstrap.md) records the blocked commands and the exact operator sequence that finishes the proof. `tests/vm/boot-smoke.sh` carries an opt-in `POST_LOGIN_CMD` hook to capture that run (#70).
- Project-scoped rootless agent containers are not exercised by the image tests here. [The agent container page](agent-container.md) documents the profile and how to run it (#71).
