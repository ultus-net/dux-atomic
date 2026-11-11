# Disk encryption and Secure Boot policy (issue #54)

Status: record of options for an operator decision, not a decision. Cutoff
2026-11-12. Everything below is read-only research: no code, manifest,
installer, or workflow changed. Commands that need target hardware are written
out rather than run.

## Outcome

Neither policy can be settled from CI. The install path this repo documents,
`bootc install to-disk` from a privileged container, cannot produce a LUKS root
with a fallback unlock. Upstream tracks that path as broken ([#421]) and tracks
install-time passphrase and recovery-key enrolment as open work ([#477],
[#1329]). Upstream recommends setting encryption up independently of bootc and
pointing `bootc install to-filesystem` at the mounted filesystem, and that is
the only path that can carry a recovery key today.

Secure Boot state is unknown on the laptop, no boot with it enabled has been
recorded on either target, and the VM test has neither Secure Boot nor a TPM.
The approved design forbids turning Secure Boot off on the laptop to simplify a
recipe [S1], so that machine cannot be installed on until its firmware state is
recorded.

## What is known and what is not

| Item | State | Source |
| --- | --- | --- |
| Laptop encryption requirement | Unrecorded, named a migration preflight check | [S1] |
| Laptop Secure Boot state | Unknown | [S1] |
| Desktop Secure Boot state | Disabled today | [S1] |
| Installing the laptop with Secure Boot off | Forbidden by the design | [S1] |
| A boot with Secure Boot enabled | Never recorded | [S2] |
| An encrypted install on this image | Never run | [S2] |
| The shipped initramfs unlocking a LUKS root | Unknown, no test asserts it | [S2] |
| A LUKS install with a recovery key | Not available upstream | [S3], [S4], [S7] |
| Secure Boot and TPM in the VM test | Neither present | [S5] |

## The three options

| Option | What it costs | What an install test proves | What it leaves unproven |
| --- | --- | --- | --- |
| 1. No encryption | Nothing changes from today's command | The install, boot, greeter, and account path already covered | Every LUKS and TPM2 claim. Data at rest is unprotected. |
| 2. LUKS with TPM2 unlock plus a recovery key | A separate `/boot`, a TPM2 enrolment, a recovery key stored off the machine, re-enrolment after any change that moves the bound PCRs | Automatic unlock on that machine, and the recovery key unlocking when the TPM is absent | The install path cannot produce it today ([#421], [#477], [#1329]), so it needs a pre-step this repo does not have. |
| 3. LUKS with a passphrase | One prompt per boot, and a passphrase recovery story | Encryption, and a fallback that does not depend on the TPM | Automatic unlock. The prompt replaces the TPM rather than adding to it. |

### Option 1: no encryption

Today's command is `bootc install to-disk --wipe --filesystem btrfs` against
`:latest` [S2]. It writes the discoverable root partition, injects
`root=UUID=<uuid>`, and creates no `/boot` partition, which the installer only
creates for LUKS [S6]. Every green result the repo has so far is this option.

### Option 2: LUKS with TPM2 unlock plus a recovery key

`bootc install to-disk --block-setup tpm2-luks` exists, and `tpm2-luks` is one
of the two accepted values [S6]. It creates a separate `/boot` because GRUB
cannot read an encrypted `/boot` [S7]. Upstream still tells new deployments to
use `install to-filesystem` for anything more complex than a plain root,
LUKS included [S6], and to set encryption up independently of bootc [S7].

Three open upstream issues decide this option:

- [#421] reports a `tpm2-luks` install that reboots into `systemd-cryptsetup`
  failing with `Current policy digest does not match stored policy digest,
  cancelling TPM2 authentication attempt.` and `No passphrase or recovery key
  registered`, then drops to a dracut rescue shell. The report calls the
  missing failover credential a bug in the install path, not a PCR problem.
- [#477] tracks configurable password and recovery keys on a LUKS volume, and
  [#1329] tracks a LUKS password at install time. Both are open, so the
  recovery key that makes TPM2 unlock safe is exactly the part the install path
  does not enrol.
- [#476] tracks configurable PCRs. [#2089], closed, records the deadlock seen
  when install-time LUKS runs inside a container's IPC namespace, which is the
  shape of this repo's install command [S2].

The PCR binding matters beyond the installer. `systemd-cryptenroll` documents
that `--tpm2-pcrs=` binds to no PCRs when the option is absent, that volumes are
generally bound to some combination of PCRs 7, 11, and 14, and that PCR 7 is
Secure Boot state, which changes when Secure Boot is toggled or the firmware
certificate databases change [S8]. A firmware update or a Secure Boot toggle can
therefore make a PCR-7-bound key stop unsealing, which is why the recovery key is
not optional.

A test of this option would prove automatic unlock on the target, the recovery
key unlocking with the TPM absent, and `/boot` staying unencrypted by design. It
needs a pre-step that partitions the disk, runs `cryptsetup luksFormat`, enrols
with `systemd-cryptenroll --tpm2-device=auto --recovery-key`, mounts the result,
and then runs `bootc install to-filesystem`. Nothing in this repo does that, and
`tests/vm/make-disk.sh:82` builds an unencrypted qcow2 [S9].

### Option 3: LUKS with a passphrase

The same pre-step, minus the TPM2 enrolment, with the passphrase set by
`cryptsetup luksAddKey` or `systemd-cryptenroll --password` [S8]. It needs no TPM
and survives a firmware update, because the fallback is the primary credential.
The cost is one prompt per boot, and that prompt is a console prompt: the only
kernel argument the image adds is `plymouth.enable=0` [S10], so there is no
splash to draw an unlock dialog.

Anaconda's kickstart `--encrypted` option is upstream's documented route for
LUKS during an install [S7]. The Anaconda ISO path is unbuilt and unconfirmed on
this image [S2], so it does not rescue the recommended to-disk path.

## What a LUKS root changes for this image

- **Root discovery.** The image ships shim and GRUB, not systemd-boot [S2].
  `bootc install to-disk` injects `root=UUID=<uuid>` by default, and discoverable
  partition auto-discovery needs a bootloader that implements the Boot Loader
  Interface, which systemd-boot always does and GRUB only with newer builds that
  include the `bli` module [S6]. With LUKS, upstream expects either discoverable
  partitions or a `root=` plus `luks.uuid` pair [S7]. Which of those this
  image's GRUB produces is unverified.
- **Initramfs.** Unlocking needs the crypt module and `systemd-cryptsetup` in the
  initramfs, and TPM2 unlocking also needs `tpm2-tss` there [S3]. The image
  carries no dracut configuration and no bootc install fragment [S2], so this
  depends on the base image. One command settles it on a booted candidate:

  ```bash
  lsinitrd -m "/boot/initramfs-$(uname -r).img" | grep -E '^(crypt|tpm2-tss)$'
  ```

  `lsinitrd -m` lists the dracut modules inside the image [S11].
- **Day-2 updates.** `bootc upgrade` operates on the mounted root filesystem with
  LUKS underneath included [S7], so updates need no special handling.
  `--target-imgref` still names `:latest` [S2], so an encrypted install keeps the
  promoted channel.
- **Ownership.** The encryption setup belongs to whoever builds and maintains the
  image or installer, not to bootc [S7]. A reinstall repeats the pre-step, and a
  lost recovery key is data loss rather than a support case.

## Secure Boot

One command reports the state. `bootctl status` prints a `Secure Boot:` line and
a `TPM2 Support:` line, and the man page example shows
`Secure Boot: disabled (setup)` [S12]. `mokutil --sb-state` prints the Secure
Boot state alone [S13].

The image carries Fedora's `shim-x64`, `shim-ia32`, and `grub2-efi-x64` [S2], so
a Secure Boot machine should accept the signed boot chain and signed kernel.
That is an expectation from the package list, not a recorded boot.

Three constraints apply:

- The design forbids disabling laptop Secure Boot to simplify a recipe, and
  forbids claiming that container signing satisfies Secure Boot [S1]. A cosign
  signature on the image says nothing about the firmware trust chain.
- The desktop has Secure Boot disabled today, and the NVIDIA variant needs the
  Universal Blue MOK key enrolled before a Secure Boot desktop can load the
  driver. The mechanics and the enrolment path are in the variant plan, section
  4 [S14], and are not repeated here.
- Laptop Secure Boot state and employer requirements are deployment gates [S1],
  so the state is an input to the LUKS decision as well: it decides what a
  future PCR-7 change means.

## What CI can and cannot prove

| Check | Today | What it would need |
| --- | --- | --- |
| UEFI boot, greeter, serial login | Covered on plain OVMF, no Secure Boot, no TPM [S5] | Nothing |
| Boot with Secure Boot enabled | Not covered | A Secure Boot OVMF firmware and a firmware key database, or hardware. `tests/vm/boot-smoke.sh:34-53` searches only the plain OVMF pairs |
| TPM2 unlock | Not covered | An emulated TPM in the VM. CI installs `podman qemu-system-x86 qemu-utils ovmf` and no TPM emulator [S5], and `tests/vm/boot-smoke.sh:99-109` passes no TPM device |
| LUKS unlock at all | Not covered | An encrypted disk. The builder is invoked with `--type qcow2 --rootfs btrfs` [S9], and the bootc migration doc documents no LUKS option |
| The recovery key unlocking | Not covered | The above plus a scripted answer to the prompt |
| A PCR change leaving the system bootable | Not covered | Two enrolments across a firmware or Secure Boot change, on hardware |

A green install test that reaches the greeter proves option 1 only. It does not
carry over to options 2 or 3, and it should not be cited as evidence for them.

## What would settle this

1. Record the firmware state on both machines with `bootctl status`, plus the
   laptop model, dock, and employer encryption requirement the design asks for
   [S1].
2. Decide whether the laptop requires encryption at rest. Employer policy
   decides that, not this repo.
3. If option 2 or 3 is chosen, write the pre-step as a documented procedure and
   try it first on the desktop, where Secure Boot is already off.
4. Settle the initramfs question in the same run with `lsinitrd`, before
   trusting any unlock result.
5. Then write the install procedure into `docs/install.md` and record the
   observed result under `docs/research/`.

## Unconfirmed

- Whether the shipped initramfs contains the crypt module and
  `systemd-cryptsetup`.
- Whether `tpm2-tss` is in the image and in its initramfs.
- Which PCRs `--block-setup tpm2-luks` binds, and whether it still fails the way
  [#421] reports on bootc 1.17.1.
- Whether this image's GRUB gives bootc the Boot Loader Interface that
  discoverable partition auto-discovery needs.
- Whether `bootc-image-builder` can produce an encrypted disk artifact. The
  bootc migration doc documents no such option [S9].
- Whether the laptop's firmware, dock, or employer policy adds a requirement
  beyond the two policies above.

## Sources

- [S1] Approved design, `docs/superpowers/specs/2026-11-09-dux-atomic-design.md`:
  hardware table (lines 70-74), the record-the-firmware-state instruction (line
  78), the migration preflight paragraph (line 80), and Secure Boot constraints
  (lines 345-348).
- [S2] `docs/install.md`: install command (lines 27-36), no install fragment
  (line 38), ISO path (lines 44-59), LUKS section (lines 78-82), Secure Boot
  section (lines 84-88).
- [S3] bootc issue #421, "install to-disk with LUKS + TPM broken", updated
  2026-07-10: <https://github.com/bootc-dev/bootc/issues/421>
- [S4] bootc issues #476, #477, #1329 (open) and #2089 (closed):
  <https://github.com/bootc-dev/bootc/issues/476>, `/477`, `/1329`, `/2089`.
- [S5] `tests/vm/boot-smoke.sh:34-53` (plain OVMF pairs only), `:99-109` (no TPM
  device), and `.github/workflows/ci.yml:89` (the packages the image job
  installs).
- [S6] `bootc install to-disk` man page: `--block-setup` values, the `/boot`
  partition created only for LUKS, root discovery modes, and the `bli`
  requirement for GRUB:
  <https://bootc.dev/bootc/man/bootc-install-to-disk.8.html>
- [S7] "Disk encryption (e.g. LUKS)": the independent-setup recommendation, the
  `/boot` requirement for `tpm2-luks`, installer ownership of the setup, the
  `root=` plus `luks.uuid` guidance, and the `install to-filesystem` scope:
  <https://bootc.dev/bootc/bootc-filesystem-encryption.7.html>
- [S8] `systemd-cryptenroll` man page, systemd 262: `--tpm2-pcrs=` default, the
  PCR table with PCR 7 as Secure Boot state, `--recovery-key`, `--password`, and
  the key roll-over limitation:
  <https://www.freedesktop.org/software/systemd/man/latest/systemd-cryptenroll.html>
- [S9] `tests/vm/make-disk.sh:82`, and the bootc migration doc, which documents
  no LUKS option:
  <https://github.com/osbuild/image-builder/blob/main/doc/20-advanced/20-bootc/50-migration.md>
- [S10] `overlay/usr/lib/bootc/kargs.d/20-plymouth.toml`, the only kernel
  argument the image adds.
- [S11] `lsinitrd` man page, `-m` and the image argument:
  <https://github.com/dracut-ng/dracut-ng/blob/main/man/lsinitrd.1.adoc>
- [S12] `bootctl` man page, `status` and its output example:
  <https://www.freedesktop.org/software/systemd/man/latest/bootctl.html>
- [S13] `mokutil` man page, `--sb-state`:
  <https://manpages.ubuntu.com/manpages/noble/man1/mokutil.1.html>
- [S14] `docs/research/2026-11-12-nvidia-variant-plan.md`, section 4.

[#421]: https://github.com/bootc-dev/bootc/issues/421
[#476]: https://github.com/bootc-dev/bootc/issues/476
[#477]: https://github.com/bootc-dev/bootc/issues/477
[#1329]: https://github.com/bootc-dev/bootc/issues/1329
[#2089]: https://github.com/bootc-dev/bootc/issues/2089
