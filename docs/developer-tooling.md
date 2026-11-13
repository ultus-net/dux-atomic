# Developer and sysadmin tooling

The image serves a machine that is a sysadmin's first and a developer's second. That ordering decides who owns each tool: the image ships what has to work on a broken machine and what needs root, and the user-space layers arrive later.

## Delivery split

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

Every user tool the dotfiles install appears in this table, so the split can be checked by reading this page instead of diffing two repositories.

## Why the image stops at the compiler

A tool belongs in the image when one of three things is true. It needs root or a kernel capability, such as `tcpdump` and `strace`. It has to work before the first successful user login, which the compiler and Node both do. Or its version must match what the build and tests use.

Everything else stays out. Homebrew packages update without an image rebuild, a Flatpak app updates on its own cadence, and an operations container carries the cloud CLIs that would otherwise pin `kubectl` to the OS release. The split keeps the image small and keeps a routine tool upgrade out of a deployment.

## Verification

`tests/verify-image.sh` covers the layer in three ways. The manifest-wide `rpm -q --whatprovides` call proves every package name resolves in the built image. A Node check runs `node --version` and requires 22.18 or newer, because that is where the dotfiles get default TypeScript type stripping. A second check runs `npm --version` and fails when the npm package is missing, which is the failure that would silence every dotfiles npm global. `tests/test-static.sh` reds when either probe, the 22.18 floor, or either manifest name leaves the repository, so a later edit cannot drop the contract quietly.

`manifests/packages-common.lock` records the Fedora NEVRA of each new name. Fedora lines float with the updates repository, so the lock is a record rather than a drift gate for them, as [Build](build.md) explains.

## Known gaps

- `lazygit` and `yazi` are not in the Fedora 45 repositories, so no image test covers them. The dotfiles `Brewfile` is the intended delivery path and does not list them yet.
- The image ships a compiler and its headers but no `cmake` or `meson`. A native build needs those from Homebrew or a Distrobox container.
- No test launches an interactive session as the operator and runs a tool. The checks above prove the packages exist and the two runtimes execute.
