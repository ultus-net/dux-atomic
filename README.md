# dux-atomic

[![ci](https://github.com/ultus-net/dux-atomic/actions/workflows/ci.yml/badge.svg)](https://github.com/ultus-net/dux-atomic/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A planned Fedora bootc developer and gaming workstation for two machines, built on Universal Blue's `base-main`.

![The Dux desktop after a first login: the DMS bar on a niri session](docs/assets/dux-desktop.png)

The build definition follows the Universal Blue image-template. The generic image builds, boots to the greeter in a VM, and provisions the desktop on the first graphical login. CI publishes `ghcr.io/ultus-net/dux-atomic:sha-<commit>` from `main`; `:latest` moves only on a manual promotion.

## Status

| Area | State |
| --- | --- |
| Base image | Universal Blue `base-main`, Fedora 45, floating tag while we prototype |
| Generic x86_64 image | Builds, boots to the greeter in a VM, and provisions the desktop on first login |
| Desktop | niri, Dux Modular Shell, Dux Greeter, Ghostty, and an Xfce X11 fallback |
| Applications | First desktop set only. Zed, OpenCode, Steam, Discord, Spotify, Bitwarden, Obsidian, Zen Browser, and Lutris are planned and not installed |
| NVIDIA variant | Planned, not built |
| Configuration | The existing [dotfiles repository](https://github.com/ultus-net/dotfiles) remains authoritative |
| Publishing | CI signs every published digest with cosign keyless OIDC and attests the SBOM. `:latest` moves only on a manual promotion |
| Rollback, agent isolation, snapshots | Planned: explicit rollback, project-scoped rootless agent containers, and local home snapshots. The image relies on the base's `bootc` update and rollback mechanics and ships no agent sandbox |

## Quick start

```bash
just ci-local
```

`just ci-local` runs the static gate, builds the image, and lints it. `just disk` and `just boot` take it into a VM. See [Build](docs/build.md) and [Testing](docs/testing.md).

## What's in the image

| Component | What it is |
| --- | --- |
| niri | Scrollable-tiling Wayland compositor |
| Dux Modular Shell | Desktop shell with launcher, status bar, and lock screen |
| Dux Greeter | Login greeter, with the niri session preselected |
| Ghostty | Terminal |
| Xfce | X11 fallback session |

The image ships no interactive user. A real install creates the operator account itself.

## Documentation

- [Build](docs/build.md)
- [First login](docs/first-login.md)
- [Testing](docs/testing.md)
- [CI and publishing](docs/ci.md)
- [Known gaps before promotion](docs/known-gaps.md)
- [Approved design](docs/superpowers/specs/2026-11-09-dux-atomic-design.md)
