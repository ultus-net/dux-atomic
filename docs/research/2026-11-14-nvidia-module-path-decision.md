# NVIDIA module-path decision (issue #72)

Status: decision record. Cutoff 2026-11-14. The operator chose the module path on
that date after reading `docs/research/2026-11-14-nvidia-module-signing.md`.
This record builds no variant, adds no package, and makes no Secure Boot claim.

## Decision

- **Path: `akmod-nvidia` compiled on the host, unsigned, as a documented
  exception.** The variant ships the akmod source package and builds the module
  on first boot. The module carries no signature the firmware trusts, and the
  record says so instead of implying otherwise.
- **No Secure Boot claim for the variant.** The non-NVIDIA image keeps its
  "nothing to enroll" property, because it keeps Fedora's signed kernel. A
  machine that runs the NVIDIA variant with Secure Boot on needs a local MOK
  enrollment, which is tracked as #40 and belongs to the machine's owner.
- **No new third-party repository is enabled to obtain a prebuilt module.**

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

- The image must ship `akmods`, `kernel-devel`, and a compiler for the build to
  run at first boot. It ships none of them today, so the variant needs a
  manifest addition before it can boot with a working module.
- The first boot is slower and can fail on a kernel mismatch. That failure mode
  has no test yet, because the variant has never been built.
- Secure Boot on NVIDIA hardware needs a per-machine MOK enrollment, which is
  the exception's price and is recorded as #40 rather than hidden.

## What this record does not do

- The variant is still unbuilt, unlocked, and unpublished
  (`docs/known-gaps.md:4`).
- No `nvidia.ko` exists, so no `modinfo -F signer` output was read.
- The akmod build has never run against the pinned kernel.
- No boot on NVIDIA hardware is recorded, with Secure Boot off or on.

## Follow-up work

Issue #72 keeps the plan's remaining item, build and publish the variant under
its own tag, plus one the plan does not list: add `akmods`, `kernel-devel`, and a
compiler to the variant's manifest, because the akmod build at first boot needs
them and the image ships none today. A boot record on NVIDIA hardware follows,
and the unsigned module must be visible in it. The roadmap's Task 6 carries the
same two items it had.

## What would reverse this

A repository that publishes per-kernel `kmod-nvidia-<kernel>-<driver>` RPMs
containing compiled modules, and whose signing key the firmware already trusts.
Enabling it is a third-party repository decision under the repository's own
rule, so it is a deliberate change rather than a switch.
