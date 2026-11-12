# Install

The published image installs to a physical disk with `bootc install to-disk` from a Fedora live environment. That path needs no install media artifact, which matters because this repo builds only a qcow2 for the VM test (`tests/vm/make-disk.sh:81`). Read the gates before wiping either target: neither machine gets an encrypted root by policy (#54), the laptop's Secure Boot state is unrecorded, and the desktop needs the NVIDIA variant from [#40](https://github.com/ultus-net/dux-atomic/issues/40).

## What the image provides

- x86_64 UEFI boot through Fedora's `shim-x64` and `grub2-efi-x64`. The image carries no 32-bit UEFI loader (`shim-ia32`, `grub2-efi-ia32` are absent), which matters only on 32-bit UEFI firmware.
- `bootc` 1.17.1, `podman`, `cryptsetup`, `btrfs-progs`, and systemd 262.
- No login account and no password. Root is locked (`root:*` in `/etc/shadow`) and `sshd` is disabled, so a fresh install has no console or SSH login.
- No NVIDIA kernel driver. `nvidia-gpu-firmware` ships, which is firmware data rather than a driver, and `nvidia-container-toolkit` is not installed.
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

No target is installed with an encrypted root. That is the recorded policy, not an omission: the decision, what it accepts, and the upstream reasons a LUKS install is not a small change are in [Disk encryption and Secure Boot policy](research/2026-11-12-luks-secureboot-policy.md) (#54). `cryptsetup` ships, but no encrypted install has been tested here.

## Secure Boot

Secure Boot needs no per-machine enrollment on this image. The chain is Fedora's end to end: `shim-x64` and `grub2-efi-x64` are Fedora-signed, and the pinned base keeps Fedora's kernel, whose signature is issued by `CN=fedoraca, OU=Fedora Secure Boot CA 20200709` with subject `CN=kernel-signer`. In-tree modules are signed by `Fedora kernel signing key`, so they load from the kernel's builtin keyring. Verified on the built image on 2026-11-12: the kernel's PE certificate table holds that PKCS#7 signature, and `modinfo -F signer` reports the Fedora key for `nf_tables.ko.xz` and `nouveau.ko.xz`.

No boot with Secure Boot enabled has been recorded on either target. Record `mokutil --sb-state` per machine before the install, then record the boot result after it. The desktop has Secure Boot disabled today (`docs/superpowers/specs/2026-11-09-dux-atomic-design.md:73`); enabling it should need no enrollment step, but that is unproven until one boot is recorded.

Fedora's shim is signed through Microsoft's third-party UEFI CA, so the firmware must trust that CA. Most machines ship with it enabled. Some Lenovo ThinkPad models ship with it off, and there the firmware setting has to be turned on once; that is a trust setting in firmware, not a key enrolled in the MOK list, and it survives upgrades without repeating. A Secure Boot violation at first boot on those machines points at this setting before anything else.

### Order on a fresh target

No target has run this order yet. It exists so the first install produces the evidence, and each step records what it observed.

1. Record the firmware state from the live environment with `mokutil --sb-state`, and keep the output beside the install result.
2. Turn Secure Boot off, run the install above, and boot through to the account you create.
3. Record `bootc status` and the digest the target booted.
4. Enable Secure Boot in firmware, boot again, and record the result.

Installing with Secure Boot off first separates a firmware refusal, which stops the boot before the kernel loads, from a defect in the image, which shows up after it. The disk does not depend on the answer: the install writes no key, so the same image boots either way.

The desktop's NVIDIA modules are unsigned, so that machine needs Secure Boot off or a locally signed module, which [#40](https://github.com/ultus-net/dux-atomic/issues/40) covers. The `image` job checks the kernel's signature on every build (`tests/verify-kernel-signature.sh`), so a base that stopped shipping Fedora's kernel would red CI rather than fail at first boot. The evidence, the base swap that removed the old enrollment path, and the remaining check are in [Disk encryption and Secure Boot policy](research/2026-11-12-luks-secureboot-policy.md) (#54).

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
