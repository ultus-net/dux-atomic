# NVIDIA module-path decision (issue #72)

Status: decision record, revised 2026-11-14 (iteration 3). Cutoff 2026-11-14. The
operator chose the module path on that date after reading
`docs/research/2026-11-14-nvidia-module-signing.md`, and approved moving the
compile from first boot to the image build on the same date. This record makes no
Secure Boot claim.

## Decision

- **Path: `akmod-nvidia` compiled during the image build, unsigned, as a
  documented exception.** The variant ships the akmod source package and the
  image build compiles it against the newest installed kernel. The module
  carries no signature the firmware trusts, and the record says so instead of
  implying otherwise.
- **No Secure Boot claim for the variant.** The non-NVIDIA image keeps its
  "nothing to enroll" property, because it keeps Fedora's signed kernel. A
  machine that runs the NVIDIA variant with Secure Boot on needs a local MOK
  enrollment, which is tracked as #40 and belongs to the machine's owner.
- **No new third-party repository is enabled to obtain a prebuilt module.**

## Revision 2026-11-14 (iteration 3): image build, not first boot

This section is the authoritative statement of the mechanism. The build record
measures it and the signing record keeps the package facts that led to it.

The original decision said the module is built on first boot. The image falsifies
that mechanism. `akmods.service` carries
`ConditionPathExists=!/run/ostree-booted` (line 3 of the unit), the unit is
enabled, and a bootc host is ostree-booted. `/lib` is also a symlink to `usr/lib`,
and a booted deployment mounts `/usr` read-only, so a first-boot write would fail
even without the unit condition. `akmods@.service` is a kernel-transaction
trigger and `akmods-shutdown.service` is disabled, so neither reaches a first
boot.

The operator approved compiling during the image build instead. The probe in
`docs/research/2026-11-14-nvidia-variant-build.md` shows `akmods --force
--kernels 7.3.3-300.fc45.x86_64` exiting 0 in 1:09 in a container of the variant
image, and producing the five modules with `version=620.70.06` and no signer.
The build now runs `build/build-nvidia-modules.sh` from `build/common.sh`, guarded
on an installed `akmod-nvidia`, and `build/check-nvidia-modules.sh` fails the
build when any of the five modules is missing or empty.

The revision does not change the security position: the module is still unsigned,
Secure Boot on NVIDIA hardware still needs a per-machine MOK enrollment (#40), and
no boot on NVIDIA hardware is recorded.

## Why the vendor-signed option is not available

The enabled repositories publish no per-kernel module. What they publish is:

| Fact | Evidence |
| --- | --- |
| `kmod-nvidia` is an empty meta-package, 10 KB, no files | `docs/research/2026-11-14-nvidia-module-signing.md:19` through `:26` |
| It requires `akmod-nvidia = 3:620.70.06-2.fc45` | same record, `:30` through `:34` |
| `akmod-nvidia` ships `/usr/src/akmods` sources, not a compiled module | same record, `:36` through `:46` |
| `dnf5 repoquery --available 'kmod-nvidia*'` returns only the meta-package | same record, `:48` through `:52` |
| The option table marks "vendor-signed prebuilt kmod" as not available | same record, `:86` |

The RPM signature on `akmod-nvidia` is package integrity, not a module
signature (`:96` through `:104` of the same record).

## What the exception costs

- The image ships `akmods`, kernel headers, and a compiler so the build can
  compile the module. `kernel-devel-matched` pins the headers to one kernel
  version, and `build/common.sh` fails the build when the installed devel does
  not match the newest installed kernel.
- The image build is longer, and the module is rebuilt for every kernel the base
  installs. That coupling is intended: a bootc kernel arrives with the image.
- A kernel that arrives outside an image build has no module until the next
  build. Nothing can compile one at runtime, because the unit is skipped and
  `/usr` is read-only.
- Secure Boot on NVIDIA hardware needs a per-machine MOK enrollment, which is
  the exception's price and is recorded as #40 rather than hidden.

## What this record does not do

- The variant is not built in CI, has no lock file, and is not published
  (`docs/known-gaps.md:4`).
- No boot on NVIDIA hardware is recorded, with Secure Boot off or on. The
  modules are unsigned, so a Secure Boot machine needs the #40 enrollment.
- No MOK enrollment or key is created, and no signature is applied.

## Follow-up work

Issue #72 keeps the remaining items: build the variant in CI, give it a lock file,
publish it under its own tag, and record a boot on NVIDIA hardware. The manifest
already carries `akmods`, the headers, and the compiler. The roadmap's Task 6
carries the same items.

## What would reverse this

A repository that publishes per-kernel `kmod-nvidia-<kernel>-<driver>` RPMs
containing compiled modules, and whose signing key the firmware already trusts.
Enabling it is a third-party repository decision under the repository's own
rule, so it is a deliberate change rather than a switch.
