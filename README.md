# dux-atomic

A planned Fedora bootc developer and gaming workstation for two machines.

The build definition is scaffolded from the Universal Blue image-template: the base tag is set in `Containerfile`. The generic image builds and boots to the greeter in a VM; no image has been published yet.

- Base: Universal Blue `base-main`, Fedora 45, on a floating tag while we prototype, with generic and NVIDIA variants.
- Desktop: niri, Dux Modular Shell, Dux Greeter, and Ghostty.
- Applications: Zed, OpenCode, Steam, Discord, Spotify, Bitwarden, Obsidian, Zen Browser, and Lutris.
- Configuration: the existing [dotfiles repository](https://github.com/ultus-net/dotfiles) remains authoritative.
- Safety: signed OS updates, explicit rollback, project-scoped rootless agent containers, and local home snapshots.

Read the [approved design](docs/superpowers/specs/2026-11-09-dux-atomic-design.md).

## Build

```bash
podman build -t dux-atomic:dev .
```

The `ctx` stage hands `build/`, `manifests/`, and `overlay/` to one build step, so none of them land in the final image. Packages come from `manifests/packages-common.txt`, one name per line.

## Test in a VM

```bash
sudo pacman -S --needed qemu-full edk2-ovmf
podman save localhost/dux-atomic:dev | sudo podman load
sudo tests/vm/make-disk.sh
tests/vm/boot-smoke.sh
```

`make-disk.sh` runs bootc-image-builder as root. `boot-smoke.sh` boots the qcow2 headless and asserts that `graphical.target`, `greetd`, and a live greeter session scope appear on the serial console.

QEMU's display-only `virtio-vga` has no render node, so the greeter compositor cannot paint under it. Check the rendered greeter on a GL-capable display (`virtio-vga-gl`) or real hardware; the smoke test asserts the session, not the pixels.

The image disables Plymouth (`plymouth.enable=0`), so both the VM and real hardware show the text boot instead of a splash.
