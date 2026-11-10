# Testing

## Headless boot test

```bash
sudo pacman -S --needed qemu-full edk2-ovmf
podman save localhost/dux-atomic:dev | sudo podman load
sudo tests/vm/make-disk.sh
tests/vm/boot-smoke.sh
```

`make-disk.sh` runs bootc-image-builder as root. The builder image is pinned by digest so a moving `:latest` cannot change the disk; override the pin with `BIB_IMAGE`. It adds one test account (`dux` / `dux-test` by default, override with `TEST_USER` and `TEST_PASSWORD`, skip with `NO_TEST_USER=1`) because the image ships no interactive user. Credentials reject quotes, backslashes, and newlines, which would break the generated TOML. It also sets `systemd.default_device_timeout_sec=180` on the test disk only: a TCG boot can run at half speed and miss the shipped 45s device timeout before `/boot` appears.

`boot-smoke.sh` boots the qcow2 headless, asserts that `greetd` starts, treats the greeter session line on the serial console as the fast signal, warns when `graphical.target` is not reported, then logs in as that account and asserts the live greeter session through `loginctl`. When the login probe finds no greeter session, it prints process wait channels, the `greetd` unit state, sessions, and failed units to the console, because the unprivileged test account cannot read the journal. It then starts the two first-login units the way `graphical-session-pre.target` does, and checks the niri config, the DMS binds, the dark session seed, the per-user `dms.service` link, the image-level `niri.service` binding, the preset enablement, and the greeter seed.

```bash
export TEST_USER=dux TEST_PASSWORD=dux-test
sudo --preserve-env=TEST_USER,TEST_PASSWORD tests/vm/make-disk.sh
VIRTIO_GL=1 tests/vm/boot-smoke.sh
```

sudo resets the environment by default, so pass the two variables through `--preserve-env`. The login stage needs the same credentials the disk was built with. Pass `BOOT_LOGIN=0` for a disk built with `NO_TEST_USER=1`, which runs the boot assertions only.

QEMU's `virtio-vga` exposes a render node, so the greeter session starts even on a host without GL. That does not prove the greeter painted. Set `VIRTIO_GL=1` on a host with a GPU to render with GL; the test then also asserts `/dev/dri/renderD128`. Check the rendered greeter on real hardware for the final confirmation.

## Graphical dogfood

The headless smoke test proves the greeter session starts, not that the desktop looks right. Boot the candidate disk with a real GL display and log in through the greeter:

```bash
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd /tmp/dux-vars.fd
qemu-system-x86_64 -machine q35,accel=kvm -cpu host -m 4096 -smp 2 -snapshot \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=/tmp/dux-vars.fd \
  -drive file=output/qcow2/disk.qcow2,if=virtio,format=qcow2 \
  -nic user,model=virtio-net-pci \
  -device virtio-vga-gl -display gtk,gl=on
```

Log in with the test account (`dux` / `dux-test` by default). The DMS bar, the dark background, and the DMS keybinds come from the first-login setup described in [First login](first-login.md).

The image disables Plymouth (`plymouth.enable=0`), so both the VM and real hardware show the text boot instead of a splash.

## CI boot test

GitHub-hosted runners have no `/dev/kvm`, so the boot test runs on QEMU TCG and is headless: it asserts the greeter session and the first-login units, not rendered pixels. The guest still gets a DRM render node from virtio-gpu. The workflow gives the boot 900s and `greetd` 300s to start, and `make-disk.sh` raises the test disk's device timeout to 180s because TCG throughput varies run to run. Run the graphical dogfood locally before promotion. See [CI](ci.md).
