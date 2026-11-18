# Testing

## Headless boot test

```bash
sudo pacman -S --needed qemu-full edk2-ovmf
podman save localhost/ultus-atomic:dev | sudo podman load
sudo tests/vm/make-disk.sh
tests/vm/boot-smoke.sh
```

`make-disk.sh` runs bootc-image-builder as root. The builder image is pinned by digest so a moving `:latest` cannot change the disk; override the pin with `BIB_IMAGE`. It adds one test account (`dux` / `dux-test` by default, override with `TEST_USER` and `TEST_PASSWORD`, skip with `NO_TEST_USER=1`) because the image ships no interactive user. Credentials reject quotes, backslashes, and newlines, which would break the generated TOML. It also sets `systemd.default_device_timeout_sec=180` on the test disk only: a TCG boot can run at half speed and miss the shipped 45s device timeout before `/boot` appears.

### A promoted digest

Test the digest the registry promoted, not the tag, because the tag can move between the pull and the boot:

```bash
digest=$(skopeo inspect docker://ghcr.io/ultus-net/ultus-atomic:latest --format '{{.Digest}}')
sudo podman pull ghcr.io/ultus-net/ultus-atomic@"$digest"
rm -rf output
sudo tests/vm/make-disk.sh ghcr.io/ultus-net/ultus-atomic@"$digest" output
```

`make-disk.sh` refuses an image that is not in rootful podman storage, hence the explicit pull. The `skopeo inspect` call is the same one the promotion record uses, so this digest matches the recorded one. `output/` holds only bootc-image-builder output and is gitignored, and `make-disk.sh` does not clear it, so `rm -rf output` drops an earlier candidate's disk that later commands on this page would otherwise boot.

`boot-smoke.sh` boots the qcow2 headless, asserts that `greetd` starts, treats the greeter session line on the serial console as the fast signal, warns when `graphical.target` is not reported, then logs in as that account and asserts the live greeter session through `loginctl`. When the login probe finds no greeter session, it prints process wait channels, the `greetd` unit state, sessions, the `/dev/dri` entries, and failed units to the console, because the unprivileged test account cannot read the journal. It then starts the two first-login units the way `graphical-session-pre.target` does, and checks the niri config, the DMS binds, the dark session seed, the per-user `dms.service` link, the image-level `niri.service` binding, the preset enablement, and the greeter seed.

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

`.vm/dogfood_login.py` drives that login and asserts the session instead of leaving it to the eye:

```bash
DOGFOOD_PROBE=7 python3 .vm/dogfood_login.py .vm/dogfood-7 output/qcow2/disk.qcow2
```

Probe 7 logs in on the serial console, clicks through the greeter's user picker, types the password, then polls `niri.service` and `dms.service` as the user. It exits 0 only when both report `active`, and it writes screenshots to the run directory, so give each candidate its own directory. The driver is local and untracked: `.gitignore` excludes `.vm/`, so a fresh clone has the procedure but not the driver.

The image disables Plymouth (`plymouth.enable=0`), so both the VM and real hardware show the text boot instead of a splash.

## Hardware install and UAT

No build of this image has run on physical hardware. The VM covers the greeter session and the first-login units and nothing else: it never logs in through the greeter's picker, never starts the Xfce fallback or a second session, and never renders the desktop ([Known gaps](known-gaps.md)). This section is the order that closes those gaps, and the evidence to keep for each check.

### Record the machine first

Four answers decide how the rest of the run goes, and they belong in the UAT record below before the disk is touched:

| Fact | Command | Why it decides |
| --- | --- | --- |
| Machine and firmware | `dmidecode -s system-product-name`, `bootctl status` | Secure Boot state has never been recorded on either target (#54) |
| GPU | `lspci -nn \| grep -Ei 'vga\|3d'` | The desktop needs the NVIDIA variant (#94) and a MOK enrollment (#95); the laptop takes the generic image |
| Target disk | `lsblk -o NAME,SIZE,MODEL,TRAN` | `bootc install to-disk --wipe` erases the whole device |
| Network at install | `curl -sI https://ghcr.io/v2/` | The installer pulls the image; anonymous GHCR access is enough |

The install leaves no encrypted root on either machine, by policy (#54). The disk is wiped and the data on it is unprotected at rest, which is accepted rather than overlooked.

### Install

The image must exist under the reference the install records. `:latest` moves only on a manual promotion (`docs/ci.md`), so install the promoted tag or, before the first promotion, the `sha-<commit>` tag, and pass that same reference as `--target-imgref` so day-2 updates follow it.

```bash
lsblk
sudo podman run --rm --privileged --pid=host --ipc=host \
  -v /var/lib/containers:/var/lib/containers \
  -v /dev:/dev \
  --security-opt label=type:unconfined_t \
  ghcr.io/ultus-net/ultus-atomic:latest \
  bootc install to-disk --wipe --filesystem btrfs \
  --target-imgref ghcr.io/ultus-net/ultus-atomic:latest \
  /dev/nvme0n1
```

The image ships no account and locks root, so the install ends with no login at all. Create the first account before the first graphical login, then reboot into the greeter.

### The checks

Each row earns its place because the VM cannot reach it. A pass means the evidence named beside it exists, not that the screen looked right.

| Check | How | Evidence to keep |
| --- | --- | --- |
| Secure Boot boot | Boot with firmware Secure Boot on | `bootctl status` showing `SecureBoot: enabled`, and the boot completing to the greeter |
| Greeter | Pick the account in the user picker and log in | Screenshot of the picker and of the session after login |
| First login provisioning | `systemctl --user status ultus-atomic-desktop.service` | Unit `active`, completion marker present, `~/.config/niri/config.kdl` written, `dms.service` `active` |
| Desktop | Bar, launcher, Ghostty, a screenshot | Screenshot, and `systemctl --user is-active dms.service` |
| Xfce fallback | Log out, choose the Xfce X11 session | Session runs, and `niri.service` and `dms.service` are absent from it |
| Second session | Start a second session while one runs | Both sessions listed by `loginctl list-sessions`, no crash |
| Screen sharing | Share a screen from a browser | A live share, plus `systemctl --user status xdg-desktop-portal` |
| Applications | Flathub set present, Steam launches one game | Screenshot of the game, and `lsmod | grep ntsync` |
| Developer tooling | `node --version`, `npm --version`, then the dotfiles bootstrap | Bootstrap exit 0 and a provisioned shell (#96) |
| Update and rollback | `bootc upgrade`, reboot, then `bootc rollback`, reboot | `bootc status` before and after each step |
| Snapshots | Confirm absence | No btrbk package, timer, or config, matching #68 |

### The UAT record

One row per run, filled from the checks above. Keep the digest, because a rebuild moves the image under the same tag.

| Date | Machine | Image digest | Secure Boot | Result | Notes |
| --- | --- | --- | --- | --- | --- |
| | | | | | |

## Signing policy tests

`tests/test-signing.sh` proves the signature policy itself, not GitHub's identity. It needs `podman`, `skopeo`, `curl`, and cosign v2 on `PATH`, plus a free `127.0.0.1:5000`; set `REGISTRY_PORT` when that port is taken. It runs a throwaway `registry:2`, pushes two payload tags with different digests, signs the trusted tag with one fixture key and signs the untrusted tag with a second key outside the policy, and asserts four cases through `skopeo copy --policy`: a signed tag and a signed digest are accepted, an unsigned tag is rejected for the missing signature, and the untrusted key's signature is rejected for the failed verification. Its keys, policy, `registries.d` file and logs live in a temp dir removed on exit, and it never contacts GitHub or a signing service. It needs network only for the two digest-pinned image pulls, and podman's storage keeps those images after the run. CI's `signing` job runs it after `static`.

```bash
tests/test-signing.sh
```

## CI boot test

GitHub-hosted runners have no `/dev/kvm`, so the boot test runs on QEMU TCG and is headless: it asserts the greeter session and the first-login units, not rendered pixels. The guest still gets a DRM render node from virtio-gpu. The workflow gives the boot 900s, `greetd` 300s, and the login shell prompt at least 60s to appear, and `make-disk.sh` raises the test disk's device timeout to 180s because TCG throughput varies run to run. Run the graphical dogfood locally before promotion. See [CI](ci.md).
