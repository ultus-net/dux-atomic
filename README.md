# dux-atomic

[![ci](https://github.com/ultus-net/dux-atomic/actions/workflows/ci.yml/badge.svg)](https://github.com/ultus-net/dux-atomic/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A planned Fedora bootc developer and gaming workstation for two machines, built on Fedora's own bootc image so Secure Boot needs no per-machine enrollment.

![The Dux desktop at first login: the DMS bar and Welcome dialog on a niri session](docs/assets/dux-desktop.png)

The build definition follows the Universal Blue image-template. Every green push to `main` publishes `ghcr.io/ultus-net/dux-atomic:sha-<commit>`.

## Status

| Area | State |
| --- | --- |
| Base image | Fedora `fedora-bootc:45`, pinned by digest, with Dependabot watching for a bump. Fedora signs the kernel, so Secure Boot needs no enrollment |
| Generic x86_64 image | Builds, boots to the greeter in a VM, and provisions the desktop on first login |
| Desktop | niri, Dux Modular Shell, Dux Greeter, Ghostty, and an Xfce X11 fallback |
| Applications | Steam ships in the image. Lutris follows after the gaming dogfood. Zed, Bitwarden, Obsidian, Zen Browser, Discord, and Spotify arrive from Flathub at first login; OpenCode stays a dotfiles-owned CLI |
| Developer and sysadmin tooling | The image ships a C toolchain, Node with npm, btop, and a diagnostics set. Homebrew owns the shell niceties, and a pinned container owns the cloud CLIs ([detail](docs/developer-tooling.md)) |
| NVIDIA variant | Planned, not built |
| Configuration | The existing [dotfiles repository](https://github.com/ultus-net/dotfiles) remains authoritative |
| Publishing | CI signs every published digest with cosign keyless OIDC and attests the SBOM. `:latest` moves only on a manual promotion |
| Rollback, agent isolation, snapshots | Planned: explicit rollback, project-scoped rootless agent containers, and local home snapshots. The image relies on the base's `bootc` update and rollback mechanics and ships no agent sandbox |

## Quick start

```bash
just ci-local
```

`just ci-local` runs the static gate, builds the image, and lints it. `just disk` and `just boot` take it into a VM. `just disk` needs the image in rootful podman storage; [Testing](docs/testing.md) has the load step, and [Build](docs/build.md) covers the build inputs.

## What's in the image

| Component | What it is |
| --- | --- |
| niri | Scrollable-tiling Wayland compositor |
| Dux Modular Shell | Desktop shell with launcher, status bar, and lock screen |
| Dux Greeter | Login greeter, with the niri session preselected |
| Ghostty | Terminal |
| Xfce | X11 fallback session |
| Steam | Gaming client, with gamescope and MangoHud |

The image ships no interactive user. A real install creates the operator account itself.

## Documentation

- [Build](docs/build.md)
- [Install](docs/install.md)
- [First login](docs/first-login.md)
- [Applications](docs/applications.md)
- [Developer and sysadmin tooling](docs/developer-tooling.md)
- [Testing](docs/testing.md)
- [CI and publishing](docs/ci.md)
- [Known gaps before promotion](docs/known-gaps.md)
- [Roadmap](docs/superpowers/plans/2026-11-14-tooling-and-platform-roadmap.md)
- [Approved design](docs/superpowers/specs/2026-11-09-dux-atomic-design.md)
