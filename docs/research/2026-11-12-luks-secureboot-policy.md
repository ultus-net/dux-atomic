# Disk encryption and Secure Boot policy (issue #54)

Status: decision record. Cutoff 2026-11-12. The operator decided both policies
on that date. The base swap in #59 is what makes the Secure Boot half true, and
this record's pull request changes no code, manifest, installer, or workflow.

## Decisions

- **Disk encryption: none.** Neither target gets an encrypted root. The install
  command stays `bootc install to-disk --wipe --filesystem btrfs`, and every
  green install result so far is that path.
- **Secure Boot: nothing to enroll.** The image boots on a Secure Boot machine
  with no per-machine step, because the pinned base keeps Fedora's own signed
  kernel and Fedora's shim already trusts it. There is no MOK enrollment, no
  local key, and no signing pipeline to maintain.

The first decision needs no evidence: an unencrypted install is what the
repository already does. The second is measured below, because it rests on the
base chosen in #59.

## The chain is Fedora's end to end

Firmware verifies the Fedora shim, the shim verifies Fedora's GRUB, and GRUB
verifies a kernel that Fedora's Secure Boot signer issued. Every link is a
Fedora package, so a normal Fedora trust configuration accepts the image with no
enrollment prompt.

Measured on the image built from this branch's base on 2026-11-12:

| Fact | Observation |
| --- | --- |
| Packages are Fedora's | `rpm -q` reports vendor `Fedora Project` for `kernel-core-7.3.3-300.fc45`, `shim-x64-16.1`, and `grub2-efi-x64-2.12-83.fc45` |
| Kernel is signed | `/usr/lib/modules/7.3.3-300.fc45.x86_64/vmlinuz` carries a PE certificate table of 1896 bytes holding a PKCS#7 signature (revision `0x200`, certificate type `0x2`) |
| Who signed it | `openssl pkcs7 -print_certs` on that signature prints subject `CN=kernel-signer, OU=bkernel01 kernel, OU=Fedora Secure Boot Signer, O=Red Hat, Inc.` and issuer `CN=fedoraca, OU=Fedora Secure Boot CA 20200709, O=Red Hat, Inc.` |
| Modules are signed | `modinfo -F signer` prints `Fedora kernel signing key` for `nf_tables.ko.xz` and `nouveau.ko.xz` |
| No Universal Blue key | `/etc/pki/akmods/certs/` does not exist in the image, and `mokutil-0.7.2-7.fc45` is installed for querying firmware state |

The kernel loads `Fedora kernel signing key`-signed modules from its builtin
keyring, which is why the in-tree module set needs no MOK entry either.

## What the previous base forced

Universal Blue's `base-main` replaces Fedora's kernel with one Universal Blue
signs: `ublue-os/main/build_files/install.sh:46` (`# Use Signed Kernel and
Versionlock`) bind-mounts `/kernel-rpms` built from `ghcr.io/ublue-os/akmods`,
and `ublue-os/akmods/certs/public_key.der` is the matching key (self-signed,
`CN=ublue kernel`, sha256
`4e5c68474cb133fd8984d9599762cece9100c3e6cd8a9709aeaabd85dd9e70d1`). Firmware
does not carry that key, so every machine had to enroll it in its MOK list
before first boot, with a first-boot MOTD warning and an installer hook in
support of that one step.

Choosing a base that keeps Fedora's kernel deletes that whole path: no
enrollment command in `docs/install.md`, no certificate to distribute, no hook
to maintain. That is the trade #59 made, and this record depends on it.

The cost is unchanged by the base: an akmod compiled at boot carries no
distribution signature on any base, so the NVIDIA variant needs Secure Boot off
or a locally signed module, which is [#40], not a regression.

## What the no-encryption decision means

- One unencrypted btrfs root, no separate `/boot`, no unlock prompt, no recovery
  key. That is the layout `bootc install to-disk` produces by default.
- Data at rest on either machine is unprotected. That is accepted for both
  targets and recorded here so a later reader does not treat it as an oversight.
- No LUKS test exists or is planned. The upstream reasons a LUKS install is not
  a small change are unchanged: `--block-setup tpm2-luks` is tracked as broken
  ([#421]) with install-time passphrases and recovery keys still open ([#477],
  [#1329]), and upstream recommends setting encryption up independently of bootc
  and pointing `bootc install to-filesystem` at the mounted filesystem. If the
  policy changes, that is the route to evaluate, not the to-disk flag.

## What this does not prove

- No boot of this image with Secure Boot enabled has been recorded on either
  machine. The signature is measured from the image, not from firmware.
- No script checks the kernel signature. A base bump could ship an unsigned
  kernel and CI would stay green; the checks below would catch it, and neither
  runs yet.
- The VM test has neither Secure Boot nor a TPM (`tests/vm/boot-smoke.sh:99-109`,
  `.github/workflows/ci.yml:89`), so no CI job can reach firmware state.
- Some Lenovo ThinkPad firmware ships with "Allow Microsoft 3rd party UEFI CA"
  off, and Fedora's shim is signed through that CA. Turning it on is a firmware
  trust setting, not a key enrolled in the MOK list, and it is the only manual
  step left on those machines.

## Checks worth adding

- Read the kernel's PE certificate table in `tests/verify-image.sh`, failing
  when the signature is absent. It needs no certificate pinning and would have
  caught the Universal Blue kernel on the old base.
- Bluefin's `sbverify --cert` variant (`ublue-os/bluefin/Justfile:520-563`) is
  the stricter form; it needs the Fedora CA certificate pinned in the repo.

## Sources

- [S1] This repository's `Containerfile` and `manifests/packages-common.lock`,
  read 2026-11-12: the base pin, the Fedora vendor of the kernel, shim, and GRUB
  packages, and the absence of `/etc/pki/akmods/certs/`.
- [S2] `ublue-os/main/build_files/install.sh:46` and `ublue-os/akmods/certs/public_key.der`,
  read 2026-11-12: the replaced kernel and the key it is signed with,
  sha256 `4e5c68474cb133fd8984d9599762cece9100c3e6cd8a9709aeaabd85dd9e70d1`:
  <https://github.com/ublue-os/main/blob/main/build_files/install.sh>,
  <https://github.com/ublue-os/akmods/blob/main/certs/public_key.der>
- [S3] `ublue-os/bluefin/Justfile:520-563`, the `sbverify --cert` check:
  <https://github.com/ublue-os/bluefin/blob/main/Justfile>
- [S4] Repository facts: `docs/install.md` for the install command,
  `tests/vm/boot-smoke.sh:99-109` (no TPM device), `.github/workflows/ci.yml:89`
  (no TPM emulator), `docs/superpowers/specs/2026-11-09-dux-atomic-design.md:73`
  (desktop Secure Boot disabled) and `:78` (record the firmware state before
  deployment).
- [S5] bootc issue #421, "install to-disk with LUKS + TPM broken", updated
  2026-07-10, and issues #477 and #1329:
  <https://github.com/bootc-dev/bootc/issues/421>

[#421]: https://github.com/bootc-dev/bootc/issues/421
[#477]: https://github.com/bootc-dev/bootc/issues/477
[#1329]: https://github.com/bootc-dev/bootc/issues/1329
[#40]: https://github.com/ultus-net/dux-atomic/issues/40
