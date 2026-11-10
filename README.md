# dux-atomic

[![ci](https://github.com/ultus-net/dux-atomic/actions/workflows/ci.yml/badge.svg)](https://github.com/ultus-net/dux-atomic/actions/workflows/ci.yml)

A planned Fedora bootc developer and gaming workstation for two machines.

The build definition is scaffolded from the Universal Blue image-template: the base tag is set in `Containerfile`. The generic image builds and boots to the greeter in a VM. CI publishes `ghcr.io/ultus-net/dux-atomic:sha-<commit>` from `main`; `:latest` moves only on a manual promotion dispatch.

- Base: Universal Blue `base-main`, Fedora 45, on a floating tag while we prototype. The generic x86_64 image builds and boots in a VM. An NVIDIA variant is planned and not built.
- Desktop: niri, Dux Modular Shell, Dux Greeter, Ghostty, and an Xfce X11 fallback.
- Applications: the first desktop set only. Zed, OpenCode, Steam, Discord, Spotify, Bitwarden, Obsidian, Zen Browser, and Lutris are planned and not installed.
- Configuration: the existing [dotfiles repository](https://github.com/ultus-net/dotfiles) remains authoritative.
- Safety: CI signs every published digest with cosign keyless OIDC and attests the SBOM. Explicit rollback, project-scoped rootless agent containers, and local home snapshots are planned. The current image relies on the base's `bootc` update and rollback mechanics and ships no agent sandbox.

Read the [approved design](docs/superpowers/specs/2026-11-09-dux-atomic-design.md).

## Build

```bash
podman build -t dux-atomic:dev .
```

The `ctx` stage hands `build/`, `manifests/`, and `overlay/` to one build step, so none of them land in the final image. Packages come from `manifests/packages-common.txt`, one name per line.

## CI

`.github/workflows/ci.yml` runs on every pull request, every push to `main`, and manual dispatch. Every action is pinned to a commit SHA, and the job that runs PR code holds only `contents: read`.

- `static` runs `tests/lint.sh`: shell syntax, shellcheck, `tests/test-static.sh`, hadolint, and actionlint. `tests/lint.sh` pins the linter images by digest, and `just check` runs the same script.
- `image` builds the image, runs `tests/verify-image.sh` (`bootc container lint` and `systemd-analyze verify`), generates an SPDX SBOM with syft, builds the qcow2 with bootc-image-builder, and runs `boot-smoke.sh`. It then scans with trivy and uploads the report. The scan is report-only until the Fedora base findings are triaged (#3).
- `publish` runs only on `main`, holds the write token and OIDC identity, and runs no repository code. It loads the built artifact, pushes `:sha-<commit>`, signs the digest with cosign keyless OIDC, attests the SBOM, and verifies both the signature and the attestation.
- A `workflow_dispatch` on `main` with `promote` set copies the signed manifest to `:latest` and asserts the registry digest. A failed copy leaves the previous tag, alerts, and needs a human retry. A push never moves `:latest`.
- `static` and `image` are required checks on `main`; a red hosted `image` run blocks merge.
- The `ghcr` environment is the approval hook. Add required reviewers in the repository settings to gate publication.
- The first push creates a private GHCR package. Set the package visibility to public in the package settings if anonymous pulls are wanted.

GitHub-hosted runners have no `/dev/kvm`, so the boot test runs on QEMU TCG and is headless: it asserts the greeter session and the first-login units, not rendered pixels. The guest still gets a DRM render node from virtio-gpu. Run the graphical dogfood locally before promotion. Record the first hosted run as the TCG baseline and adjust `BOOT_TIMEOUT` from it.

`just check` mirrors the static gate. `just build`, `just lint-image`, `just disk`, and `just boot` cover the rest.

## Test in a VM

```bash
sudo pacman -S --needed qemu-full edk2-ovmf
podman save localhost/dux-atomic:dev | sudo podman load
sudo tests/vm/make-disk.sh
tests/vm/boot-smoke.sh
```

`make-disk.sh` runs bootc-image-builder as root. The builder image is pinned by digest so a moving `:latest` cannot change the disk; override the pin with `BIB_IMAGE`. It adds one test account (`dux` / `dux-test` by default, override with `TEST_USER` and `TEST_PASSWORD`, skip with `NO_TEST_USER=1`) because the image ships no interactive user. Credentials reject quotes, backslashes, and newlines, which would break the generated TOML. `boot-smoke.sh` boots the qcow2 headless, asserts that `greetd` starts and that a live greeter session scope appears on the serial console, warns when `graphical.target` is not reported, then logs in as that account. It starts the two first-login units the way `graphical-session-pre.target` does, then checks the niri config, the DMS binds, the dark session seed, the per-user `dms.service` link, the image-level `niri.service` binding, and the preset enablement.

```bash
sudo TEST_USER=dux TEST_PASSWORD=dux-test tests/vm/make-disk.sh
VIRTIO_GL=1 TEST_USER=dux TEST_PASSWORD=dux-test tests/vm/boot-smoke.sh
```

The login stage needs the same credentials the disk was built with. Pass `BOOT_LOGIN=0` for a disk built with `NO_TEST_USER=1`, which runs the boot assertions only.

QEMU's `virtio-vga` exposes a render node, so the greeter session starts even on a host without GL. That does not prove the greeter painted. Set `VIRTIO_GL=1` on a host with a GPU to render with GL; the test then also asserts `/dev/dri/renderD128`. Check the rendered greeter on real hardware for the final confirmation.

A real install creates the operator account itself, either in the installer or with `useradd -m`. The image never ships a login account or a password.

## First login

The image never runs the Dux setup for root. On the first graphical session, `dux-atomic-desktop.service` runs `dms setup headless --compositor niri --terminal ghostty --skip-existing` as that user. It writes only under the user's home: the niri config, the DMS binds, the Ghostty config, and the `niri.service` binding for `dms.service`. A user who already has a niri config without the DMS includes, such as a dotfiles-managed account, skips the setup.

The unit records success with `${XDG_STATE_HOME:-$HOME/.local/state}/dux-atomic/desktop-setup.done`, matching the unit's `%S`. `ExecCondition` runs the setup for a fresh home or a dms-generated config without that marker, so a failed or timed-out run retries on the next login instead of leaving a half-written home skipped forever. The marker is written only after `dms setup` exits 0.

The desktop retry's failure contract is retry on the next login until it succeeds. Each attempt is capped at 120 seconds, and there is no attempt limit, so a permanently failing setup costs up to 120 seconds on every login. A cap is a pre-promotion follow-up. The greeter seed's contract is retry on the next boot, described below.

`dux-atomic-dms-defaults.service` seeds `~/.local/state/dms/session.json` with a dark DMS background, so the first session is not a blank compositor surface. Replace it with a wallpaper from the Dux library when you want the full documented look.

Both units are enabled through `overlay/usr/lib/systemd/user-preset/01-dux-atomic.preset`, which `build/common.sh` applies with `systemctl --global preset`. `dms.service` is not globally enabled: `overlay/usr/lib/systemd/user/niri.service.wants/dms.service` binds it to the niri session, so the shell starts for every niri login, including an account that already owns a niri config and skips the setup. The Xfce fallback never starts `niri.service`, so it never starts the Wayland shell. Both units skip root and the greeter account.

The greeter keeps the upstream `dms-greeter --command niri` config. Do not copy Zirconium's `[general] service = "greetd-spawn"` stanza: Fedora's greetd 0.10.3 does not ship a `greetd-spawn` binary.

The greeter picks session index 0 when it has no memory, and the desktop files load in asynchronous order. `dux-atomic-greeter-defaults.service` runs before `greetd.service` and seeds `/var/cache/dms-greeter/.local/state/memory.json` with `lastSessionDesktopId: "niri.desktop"`, so a fresh install always opens niri. A session remembered from a previous login still wins, and any existing file, including an empty one, is left alone; delete it to re-seed.

The seed is a `Wants=` dependency, not `Requires=`, so a failed seed does not block the login. Its failure contract is retry on the next boot with the result visible in the unit journal; greetd then falls back to the first session it loads, which may be the Xfce fallback. Check `systemctl status dux-atomic-greeter-defaults.service` after a first boot.

## Dogfood the graphical desktop

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

Log in with the test account (`dux` / `dux-test` by default). The DMS bar, the dark background, and the DMS keybinds come from the first-login setup above.

The image disables Plymouth (`plymouth.enable=0`), so both the VM and real hardware show the text boot instead of a splash.

## Known gaps before promotion

- `console=ttyS0,115200` ships a serial getty to every install. It is a deliberate VM-test and recovery console for this branch; gate it behind a test build before publishing.
- The image has no NVIDIA variant, application set, agent sandbox, or snapshot automation yet. The README marks these as planned.
- The VM test covers the greeter and a serial login. It does not log in through the greeter, start a second session, or exercise the Xfce fallback.
- CI runs the boot test on TCG and does not render or inspect the desktop. The graphical dogfood stays a local pre-promotion step.
- `bootc-image-builder` is pinned in `tests/vm/make-disk.sh`, but the base image tag floats and the COPR packages are unpinned (#2).
- The first-login retry has unit fixtures and a VM marker assertion, but no partial-home VM coverage yet. Rebuild and re-run the graphical dogfood after the retry change.
