# Dell Pro 14 PC14250 (laptop target)

Reference record for the laptop that takes the generic image. The operator
supplied this brief on 2026-11-20, when the machine ran Bluefin 44
`bluefin-dx`. No build of this repo has been installed on it. The approved
design asks for the model and Secure Boot state before deployment
(`docs/superpowers/specs/2026-11-09-dux-atomic-design.md`), and this page
carries the model, the device IDs, and the boot-path facts.

NixOS and any dual-boot layout are another agent's task. This page covers the
bootc image only, and it assumes the disk is not repartitioned for a dual boot.

## Build and test host

The laptop builds and tests the image itself. These versions were verified on
the machine.

| Tool | Version |
| --- | --- |
| podman | 5.8.9 |
| buildah | 1.43.5 |
| bootc | 1.17.1 (fc44) |
| composefs | 1.0.8 |
| dracut | 108-8.fc44 |
| skopeo, rpm-ostree, ostree | present |

- Rootless podman works: `podman unshare true` exits 0.
- Rootless storage uses `graphDriverName: overlay` with `Native Overlay Diff:
  "true"`, so overlayfs runs natively over the host's btrfs. No fuse-overlayfs
  fallback is needed.
- Rootless graph root is `/var/home/csh/.local/share/containers/storage`.
- `bootc status`, `bootc switch`, and `bootc rollback` require root. Running
  `bootc status` as a normal user fails with "must be executed as the root
  user". Expect `sudo` on every bootc command.
- The host is genuinely bootc-managed. `/usr/lib/bootc/` holds
  `initramfs-setup`, `install`, `kargs.d`, `storage`, and `bound-images.d`, so it
  is not a legacy rpm-ostree-only host.

## Hardware the image must support

Every row below is a boot failure or a missing device when the image omits it.

| Subsystem | IDs | Driver | Required in the image |
| --- | --- | --- | --- |
| CPU | Intel Core Ultra 7 255U, Arrow Lake-U, 12C/14T | `intel_pstate`, `intel_rapl` | Intel microcode |
| Storage | NVMe behind Intel VMD `[8086:7d0b]`, disk at `10000:e1:00.0` | `vmd`, `nvme` | **`vmd` and `nvme` in the initramfs** |
| GPU | Intel Graphics `[8086:7d41]` | `i915` (verified; `xe` is also built, do not switch) | `intel-gpu-firmware` (GuC/HuC) |
| WiFi | Arrow Lake CNVi / AX211 `[8086:7740]` | `iwlwifi` | `iwlwifi-mvm-firmware` |
| Bluetooth | `[8087:0033]` | `btusb` | `linux-firmware` |
| Ethernet | Realtek RTL8111/8168 `[10ec:8168]` | `r8169` | built in |
| Audio | HD Audio `[8086:7728]` with Realtek ALC269, SOF path `snd_sof_pci_intel_mtl` | `snd_sof`, soundwire | **`alsa-sof-firmware`** |
| Thunderbolt | JHL7440 Titan Ridge `[8086:15ef]`, `[8086:15ec]` | `thunderbolt` | optional `bolt` |
| Touchpad | Elan I2C-HID `[04F3:332C]` | `hid_multitouch`, `i2c_hid` | built in |
| Webcam | Realtek `[0bda:558b]` | `uvcvideo` | built in |
| Sensors and hotkeys | Dell WMI | `dell_wmi`, `dell_laptop` | built in |
| Fingerprint | none present | n/a | do not add `fprintd` |

VMD is the highest-risk item. The root disk is reachable only through the VMD
controller. An initramfs without `vmd` boots to an emergency shell with no root
filesystem, and the failure looks like a broken image rather than a missing
module. A container build cannot detect it, so it is the item most likely to
regress silently.

## Verified-working version floor

These packages are a known-good set on this exact machine. Treat them as the
minimum bar.

| Package | Verified version |
| --- | --- |
| kernel | 7.2.11-200.fc44.x86_64 |
| dracut | 108-8.fc44 |
| linux-firmware | 20261019-1.fc44 |
| intel-gpu-firmware | 20261019-1.fc44 |
| iwlwifi-mvm-firmware | 20261019-1.fc44 |
| alsa-sof-firmware | 2025.12.2-1.fc44 |

Arrow Lake-U and the AX211 device ID `8086:7740` are recent. An image built on
a visibly older kernel or older iwlwifi firmware may boot with no WiFi, so
verify the firmware version, not just that the module loaded.

This repo pins a Fedora 45 base while the laptop runs Fedora 44. The image is
therefore ahead of the floor on every row, and the boot test compares the
installed image's versions, not Bluefin's.

## Initramfs rules

- The build runs in a container with no access to the target hardware, so a
  hostonly initramfs is wrong by construction. Build a generic initramfs.
- Confirm the result contains `vmd` before shipping. Inspect it with
  `lsinitrd` and grep for `vmd`, `nvme`, `thunderbolt`, `i915`, and `iwlwifi`.
- Do not rely on the host's `/etc/dracut.conf.d`. It is empty, so there are no
  local overrides to inherit and none to copy.
- The working initramfs is 232 MiB and the kernel 19 MiB, so budget 250 MiB per
  deployment. That size drives the `/boot` capacity check below.

## Boot path facts

- The bootloader is GRUB2 with BLS. Entries live in `/boot/loader.0/entries/`,
  and `/boot/loader` is a symlink to `loader.0`. The ESP is owned by bootupd
  (`/boot/bootupd-state.json`), with the archive expected under
  `\EFI\fedora\`.
- The kernel command line in use:

  ```
  ostree=/ostree/boot.0/default/<hash>/0 rhgb quiet
  root=UUID=<host-root-uuid> vconsole.keymap=us
  rootflags=subvol=root rw
  ```

  The deployment root is btrfs `subvol=/root` (subvolid 256), with `home` 257
  and `var` 258. `/` itself is composefs over the deployment and is read-only.
  The root filesystem UUID is recorded on the host, not in this page.
- Secure Boot is disabled. That is the recorded state on 2026-11-20, and no
  signature is needed while it holds. The design also treats an employer
  requirement as a deployment gate, so recheck the state before install. If it
  is enabled, the image needs UKI signing and a shim path.
- `/boot` is ext4 on p2, 2.0G total with 1.6G free. It must hold two
  deployments, the current one and the rollback. At 250M each this fits, but
  do not ship a much larger initramfs without rechecking the free space.
- A staged update `44.20261117.1` is pending, digest `sha256:fa89...`, with 202
  upgraded and 2 added packages including 2 critical advisories. It is staged
  but not booted. Cancel it or boot it deliberately before testing, or "which
  image am I on" becomes ambiguous.
- Host layered packages, for reference only: `dms dux-files dux-greeter
  dux-search ghostty hyprland hyprland-guiutils matugen quickshell`. The image
  should bake in what it needs instead of layering on the host.

## Test loop

1. Build with rootless podman or buildah. Tag locally, and push to a registry
   the laptop can reach when `bootc switch` needs a remote reference.
2. `sudo bootc switch --transport registry <imgref>`. Confirm the exact flag
   set against bootc 1.17.1 before running it.
3. Reboot. Confirm `sudo bootc status` reports the expected image reference and
   digest.
4. Verify, on two cold boots:
   - The root filesystem mounts with no emergency shell, which proves `vmd` and
     `nvme` are present.
   - `ip link` shows `wlp0s20f3` up with firmware loaded, not just the module.
   - `glxinfo -B` or `vainfo` shows hardware acceleration on `i915`.
   - `pactl info` or `aplay -l` shows the SOF card and the ALC269 codec.
   - Suspend and resume work.
5. `sudo bootc rollback`, reboot, and confirm the previous deployment is back.
   Demonstrate this once per build. It is the whole safety net.

## Acceptance criteria

- A cold boot reaches a working desktop with no emergency shell and no manual
  kernel argument.
- WiFi, GPU acceleration, audio, and suspend/resume are verified with command
  output, not inferred from `lsmod`.
- `lsinitrd` output proves `vmd` is present, and that proof is in the run
  report.
- `bootc switch` onto the image and `bootc rollback` back are both
  demonstrated.
- Every pinned package version is justified against the version floor above.

## Repo state checked on 2026-11-20

Checked against `localhost/ultus-atomic-server:dev` (`3279dd47e7ab`, built from
the headless-server branch) and `localhost/ultus-atomic:split`. Both are Fedora
45 builds with kernel `7.3.3-300.fc45.x86_64`.

| Check | Result |
| --- | --- |
| `linux-firmware` | `20261019-1.fc45`, meets the floor |
| `intel-gpu-firmware` | `20261019-1.fc45`, meets the floor |
| `iwlwifi-mvm-firmware` | `20261019-1.fc45`, meets the floor |
| `alsa-sof-firmware` | `2026.09.2-1.fc45`, newer than the floor |
| Intel microcode | **absent**. `intel-microcode` is not installed, and `microcode_ctl 2:2.1-76.fc45` is available from the Fedora repositories |
| `vmd.ko.xz` | present in `/usr/lib/modules/7.3.3-300.fc45.x86_64/kernel/drivers/pci/controller/` |
| `nvme.ko.xz` | present under `.../kernel/drivers/nvme/host/` |
| `/etc/dracut.conf.d` | empty, as on the laptop |
| Shipped dracut config | `22-bootc-generic.conf` adds `virtiofs`; `30-bootc-standard.conf` adds `lvm crypt fips` |
| Initramfs selection | a `dracut --no-hostonly` run inside the container selected `vmd.ko.xz`, `nvme.ko.xz`, `thunderbolt.ko.xz` and `thunderbolt_net.ko.xz` before it aborted on `/root` (a container limitation, and the run produced only 111 MiB, so it is not the shipped initramfs) |
| `/boot` in the image | empty. The initramfs is built at install time, so `lsinitrd` proof belongs to the install, not the build |

Two gaps follow from that table:

- **No microcode package.** The brief lists Intel microcode as required, and no
  manifest installs it. `microcode_ctl` is the Fedora package that ships the
  early-load microcode. It is a manifest change, not a bootc or dracut one.
- **The initramfs proof is still pending.** The container cannot produce a
  complete generic initramfs, so the acceptance item stays open until
  `lsinitrd` runs on an installed system. The module selection above is
  evidence that the configuration includes VMD, not proof that the shipped
  initramfs does.

## Traps

- The staged `44.20261117.1` update applies on the next boot. Cancel it first,
  or test results get attributed to the wrong image.
- VMD makes an image silently unbootable, and a container build cannot discover
  it. That single failure mode is why the initramfs rule and the acceptance
  criterion exist.
- Rootless overlay runs natively here, so builds are fast on this btrfs. Do not
  add fuse-overlayfs to work around a problem this machine does not have.
