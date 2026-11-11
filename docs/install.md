# Install

The published image installs to a physical disk with `bootc install to-disk` from a Fedora live environment. That path needs no install media artifact, which matters because this repo builds only a qcow2 for the VM test (`tests/vm/make-disk.sh:81`). Read the gates before wiping either target: the laptop's LUKS and Secure Boot state are unresolved, and the desktop needs the NVIDIA variant from [#40](https://github.com/ultus-net/dux-atomic/issues/40).

## What the image provides

- x86_64 UEFI boot through Fedora's `shim-x64`, `shim-ia32`, and `grub2-efi-x64`.
- `bootc` 1.17.1, `podman`, `cryptsetup`, `btrfs-progs`, and systemd 262.
- No login account and no password. Root is locked (`root:*` in `/etc/shadow`) and `sshd` is disabled, so a fresh install has no console or SSH login.
- No NVIDIA kernel driver. `nvidia-gpu-firmware` and `nvidia-container-toolkit` are present, but neither is a display driver.
- Anonymous pull from GHCR, so no registry login is needed.

## Install media

Two paths exist. Use `bootc install to-disk`. The ISO path is legacy, has no artifact here, and is unconfirmed. The live environment needs podman and network access to GHCR.

### Recommended: to-disk from a live environment

Identify the target disk first. `lsblk` prints the device names, and the install erases the whole device.

```bash
lsblk
```

Run the installer from the image itself. Upstream requires `bootc install` to run inside the image being installed, with podman storage and device access passed in.

```bash
sudo podman run --rm --privileged --pid=host --ipc=host \
  -v /var/lib/containers:/var/lib/containers \
  -v /dev:/dev \
  --security-opt label=type:unconfined_t \
  ghcr.io/ultus-net/dux-atomic:latest \
  bootc install to-disk --wipe --filesystem btrfs \
  --target-imgref ghcr.io/ultus-net/dux-atomic:latest \
  /dev/nvme0n1
```

The image carries no `/usr/lib/bootc/install` fragment, so nothing pins the filesystem type; the page passes `--filesystem btrfs` explicitly to match the filesystem `tests/vm/make-disk.sh` builds and the repo's btrfs expectation. `--wipe` erases the device. `--target-imgref` sets the reference day-2 updates fetch, so installing `:latest` keeps updates on the promoted channel. Only the device name is machine specific.

`--source-imgref` is the flag for an installer that already runs inside a chroot from the image. Upstream still requires the image's chroot, so this page does not run `bootc install` directly on the live host.

The install writes no account. Do not reboot into the greeter yet; create the first account as described below.

### Alternative: an installer ISO

`bootc-image-builder` still accepts `--type iso`, and the pinned builder in `tests/vm/make-disk.sh:66` lists `iso` and `anaconda-iso` in `build --help`. Both types are legacy: the unified `image-builder` CLI documents `generic-iso` for new work, and upstream plans to remove the Anaconda ISO type. No ISO has been built or booted from this image, and the image ships neither `anaconda` nor `dracut-live`, so treat this path as unconfirmed.

```bash
mkdir -p output
sudo podman run --rm --privileged \
  --security-opt label=type:unconfined_t \
  -v "$PWD/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder@sha256:a0ee98db5bfb8337e45efb92f0c5d1a19179c85ce80a3360abc628fd1a17cc5c \
  build ghcr.io/ultus-net/dux-atomic:latest \
  --type iso --rootfs btrfs --output /output
```

The build writes an installer ISO under `output`. Anaconda supports creating the first account and setting up LUKS during the install, but neither has been exercised on this image.

## The first account

The image ships no account and no password, and `sshd` is disabled, so there is no SSH or root console to log in to. The supported way to create the first account is a one-time boot with `systemd.debug_shell` on the kernel command line. It starts `debug-shell.service` and a root shell on tty9.

At the GRUB menu, edit the boot entry and append `systemd.debug_shell` to the `linux` line, then boot. Switch to tty9 with Ctrl+Alt+F9 and run:

```bash
useradd -m -G wheel operator
passwd operator
```

`useradd -m` creates the home directory. `-G wheel` makes the account an administrator, because the image's `/etc/sudoers` grants `wheel` full sudo. The account stays locked until `passwd` sets a password. Reboot without the kernel argument, and the greeter lists the account.

This is the console path in [First login](first-login.md), with the root access made explicit. A bare `useradd -m` cannot run from a greeter with no users, because root is locked and `sshd` is disabled.

Install-time provisioning needs a builder-produced artifact. A legacy `bootc-image-builder` config can carry `[[customizations.user]]` with `name`, `groups`, `key`, and `password`, so a disk image or ISO can create the account before first boot. This repo uses that only for the VM test account.

## LUKS

`cryptsetup` ships, but no encrypted install has been tested here. Upstream recommends setting up encryption independently of bootc, then pointing `bootc install to-filesystem` at the mounted filesystem. It explicitly does not recommend `bootc install to-disk --block-setup tpm2-luks` for new deployments. The legacy Anaconda ISO is the path upstream documents for LUKS during install.

The laptop's encryption preflight is therefore not satisfied by the recommended to-disk command. Whether the shipped initramfs unlocks a LUKS root is unconfirmed, and `--block-setup tpm2-luks` is unconfirmed on this image. Gate: do not wipe the laptop until an encrypted install has been run and recorded.

## Secure Boot

The SBOM carries `shim-x64`, `shim-ia32`, and `grub2-efi-x64`, so the image contains Fedora's signed boot chain. No boot with Secure Boot enabled has been recorded on either target. The laptop's firmware state is unknown (`docs/superpowers/specs/2026-11-09-dux-atomic-design.md:78`), and this page does not assume the installed system boots with it on. Gate: record the firmware setting before wiping. If it is on, verify the Fedora shim is trusted, or turn Secure Boot off for the install and record that decision.

The desktop has Secure Boot disabled today (`docs/superpowers/specs/2026-11-09-dux-atomic-design.md:73`). The NVIDIA variant's modules are unsigned, so that machine needs Secure Boot off or a signing path, which [#40](https://github.com/ultus-net/dux-atomic/issues/40) covers.

## The desktop

The generic image does not drive the desktop's monitors. Both active displays are on the RTX 3070 (`docs/superpowers/specs/2026-11-09-dux-atomic-design.md:73`), and the image has no NVIDIA kernel driver. Arch cannot switch to bootc in place (`docs/superpowers/specs/2026-11-09-dux-atomic-design.md:81`), so the desktop needs a fresh atomic install of an NVIDIA variant that does not exist yet. Do not install the generic image on the desktop. [#40](https://github.com/ultus-net/dux-atomic/issues/40) plans the variant.

## After first boot

`bootc status` names the booted image and digest. `bootc upgrade --check` confirms the update reference resolves before you rely on it.

```bash
bootc status
sudo bootc upgrade --check
```

A fresh install has one deployment, so `bootc rollback` has nothing to switch to. After an upgrade lands, rollback reorders the deployments and returns to the previous one. `/etc` reverts to that deployment's state. Without `--apply`, the command only changes the bootloader ordering.

```bash
sudo bootc rollback --apply
```

## Sources

- `lsblk`: https://man7.org/linux/man-pages/man8/lsblk.8.html
- The `podman run` install invocation, its `--privileged`, `--pid=host`, `--ipc=host`, `-v`, and `--security-opt` flags, and `--source-imgref`: https://bootc.dev/bootc/bootc-installation.7.html
- `bootc install to-disk`, its device argument, `--wipe`, `--filesystem`, `--target-imgref`, and `--block-setup`: https://bootc.dev/bootc/man/bootc-install-to-disk.8.html
- The optional `filesystem.root.type` setting in `/usr/lib/bootc/install` fragments, and that a base image may provide a default: https://bootc.dev/bootc/man/bootc-install-config.5.html
- `mkdir -p`: https://man7.org/linux/man-pages/man1/mkdir.1.html
- `bootc-image-builder` `--type`, `--rootfs`, `--output`, the positional image, the podman flags, and `/config.toml`: https://github.com/osbuild/image-builder/blob/main/doc/20-advanced/20-bootc/50-migration.md
- `iso` and `anaconda-iso` are legacy types: https://github.com/osbuild/image-builder/blob/main/doc/20-advanced/20-bootc/20-legacy-isos.md
- The `anaconda-iso` removal plan: https://osbuild.org/docs/bootc/deprecation-notice/
- `[[customizations.user]]` and its `name`, `groups`, `key`, and `password` fields: https://osbuild.org/docs/user-guide/blueprint-reference/
- Bootc-specific blueprint and `config.toml` discovery: https://github.com/osbuild/image-builder/blob/main/doc/20-advanced/20-bootc/05-sources-of-configuration.md
- `systemd.debug_shell`, `debug-shell.service`, and tty9: https://man7.org/linux/man-pages/man8/systemd-debug-generator.8.html
- `useradd -m` and `-G wheel`: https://man7.org/linux/man-pages/man8/useradd.8.html
- `passwd`: https://man7.org/linux/man-pages/man1/passwd.1.html
- The independent LUKS recommendation and the `--block-setup tpm2-luks` warning: https://bootc.dev/bootc/bootc-filesystem-encryption.7.html
- `bootc status`: https://bootc.dev/bootc/man/bootc-status.8.html
- `bootc upgrade --check`: https://bootc.dev/bootc/man/bootc-upgrade.8.html
- `bootc rollback --apply`: https://bootc.dev/bootc/man/bootc-rollback.8.html
