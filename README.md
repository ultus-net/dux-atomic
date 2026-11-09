# dux-atomic

A planned Fedora bootc developer and gaming workstation for two machines.

The build definition is scaffolded from the Universal Blue image-template: the base tag is set in `Containerfile`. No image has been built or published yet.

- Base: Universal Blue `base-main`, Fedora 45, on a floating tag while we prototype, with generic and NVIDIA variants.
- Desktop: niri, Dux Modular Shell, Dux Greeter, and Ghostty.
- Applications: Zed, OpenCode, Steam, Discord, Spotify, Bitwarden, Obsidian, Zen Browser, and Lutris.
- Configuration: the existing [dotfiles repository](https://github.com/ultus-net/dotfiles) remains authoritative.
- Safety: signed OS updates, explicit rollback, project-scoped rootless agent containers, and local home snapshots.

Read the [approved design](docs/superpowers/specs/2026-11-09-dux-atomic-design.md).
