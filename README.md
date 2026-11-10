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

`make-disk.sh` runs bootc-image-builder as root. It adds one test account (`dux` / `dux-test` by default, override with `TEST_USER` and `TEST_PASSWORD`, skip with `NO_TEST_USER=1`) because the image ships no interactive user. Credentials reject quotes, backslashes, and newlines, which would break the generated TOML. `boot-smoke.sh` boots the qcow2 headless, asserts that `graphical.target`, `greetd`, and a live greeter session scope appear on the serial console, then logs in as that account and checks the console session.

```bash
sudo TEST_USER=dux TEST_PASSWORD=dux-test tests/vm/make-disk.sh
VIRTIO_GL=1 TEST_USER=dux TEST_PASSWORD=dux-test tests/vm/boot-smoke.sh
```

The login stage needs the same credentials the disk was built with. Pass `BOOT_LOGIN=0` for a disk built with `NO_TEST_USER=1`, which runs the boot assertions only.

QEMU's display-only `virtio-vga` has no render node, so the greeter compositor cannot paint under it. Set `VIRTIO_GL=1` to boot with `virtio-vga-gl` and an offscreen display, which gives the guest a render node; the test then also asserts `/dev/dri/renderD128`. Check the rendered greeter on real hardware for the final confirmation.

A real install creates the operator account itself, either in the installer or with `useradd -m`. The image never ships a login account or a password.

The image disables Plymouth (`plymouth.enable=0`), so both the VM and real hardware show the text boot instead of a splash.
