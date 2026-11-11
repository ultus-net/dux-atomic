# NVIDIA variant plan (issue #40)

Status: plan for operator review, not an implementation. Cutoff 2026-11-12.
Everything below is read-only research: no code, manifest, or workflow changed.
Registry digests and labels were read from the ghcr.io manifest API on the cutoff
date, so they are observations to re-verify at execution, not trust anchors.

## Outcome

Build the variant from the existing pinned `base-main` digest and add the
prebuilt `nvidia-open` kernel module from a kernel-specific `akmods-nvidia-open`
tag, pinned by digest, in a second `Containerfile` target. Both pins must name
the same kernel, and a build-time assertion must fail the build when they do
not. Do not derive from `base-nvidia`: upstream retired it.

The pair that matches the repository's current base pin at cutoff:

```text
ghcr.io/ublue-os/base-main:45@sha256:444e9e37ea581e76829772ae2a42edfdbacdd0cbc7a27085a4ed0f3d6e1336c7
ghcr.io/ublue-os/akmods-nvidia-open:main-45-7.2.15-300.fc45@sha256:d08edbb4709d2acf2b77cb507b3450a60095d39e4153a86fe0233f70a9036708
```

Both carry kernel `7.2.15-300.fc45.x86_64`; the akmods image carries
`akmod-nvidia 3:620.70.06-1.fc45`. That combination needs no base bump and no
change to the generic image.

## Evidence at cutoff

| Item | Observed value | Source |
| --- | --- | --- |
| Base pinned in `Containerfile` | `base-main:45@sha256:444e9e37…`, version `45.20261110.1`, kernel `7.2.15-300.fc45.x86_64` | [S1], [S2] |
| `base-main:45` tag at cutoff | digest `sha256:3793f5c5…`, version `45.20261111.2`, kernel `7.3.3-300.fc45.x86_64` | [S1] |
| `akmods-nvidia-open:main-45-7.2.15-300.fc45` | digest `sha256:d08edbb4…`, driver `3:620.70.06-1.fc45`, built 2026-11-11 | [S3] |
| `akmods-nvidia-open:main-45` (floating) | digest `sha256:106bebe1…`, kernel `7.3.3-300.fc45.x86_64`, driver `3:620.70.06-1.fc45` | [S3] |
| `base-nvidia:45` (retired) | digest `sha256:fd1bec61…`, version `45.20261107`, kernel `7.2.15-300.fc45.x86_64` | [S1], [S4] |
| Desktop hardware | RTX 3070, AMD iGPU, both active monitors on NVIDIA, Secure Boot disabled | [S5] |
| Laptop hardware | Intel Arrow Lake-U graphics, Titan Ridge Thunderbolt bridge, Secure Boot state unknown | [S5] |
| NVIDIA variant status | "Planned, not built" | [S6] |

The float is visible in one day: the pinned digest is kernel 7.2.15, and the
`base-main:45` tag moved to kernel 7.3.3 on 2026-11-11. The floating
`akmods-nvidia-open:main-45` moved to 7.3.3 in the same window. A variant that
pins one and floats the other builds a module for a kernel the image does not
boot.

## 1. Base candidates and recommendation

| Candidate | Kernel at cutoff | Verdict |
| --- | --- | --- |
| **A.** `base-main:45@sha256:444e9e37…` + `akmods-nvidia-open:main-45-7.2.15-300.fc45@sha256:d08edbb4…` | 7.2.15 on both | **Recommended.** Same base the generic image ships, one added build stage, and the akmods tag names the kernel so a mismatch is visible in review. |
| **B.** `base-main:45@sha256:3793f5c5…` (current tag) + `akmods-nvidia-open:main-45@sha256:106bebe1…` | 7.3.3 on both | Works today, but it bumps the generic base in the same PR and the akmods tag floats. Acceptable only if the operator wants the newer kernel now. |
| **C.** `base-nvidia:45@sha256:fd1bec61…` | 7.2.15 | Rejected. Upstream retired `base-nvidia`, `silverblue-nvidia`, and `kinoite-nvidia` in [S4]; the tag still resolves, but it is outside the maintained image set and its kernel is behind the current base. Its value is declining with no upstream fix path. |
| **D.** A full desktop NVIDIA image (`bazzite-nvidia` and similar) | n/a | Rejected. The approved design keeps those projects as reference only and does not fork them [S5]. It would replace our desktop and test surface. |

### Why the pin is two lines, not a build argument

`Containerfile` uses a literal `FROM` because Dependabot's docker ecosystem
matches a file whose name contains `containerfile` and never expands an `ARG`
into `FROM` [S7], [S8]. That removed the `BASE_IMAGE` argument the
candidate-images plan assumed [S8]. The variant therefore needs its own pinned
`FROM` line, and `tests/test-static.sh` currently counts every
`^FROM ghcr.io/ublue-os/` line and requires all of them to match `base-main`
(`tests/test-static.sh:17-27`). An akmods stage in the same file fails that
check until the assertion learns both pins.

Recommendation: one `Containerfile` with two pinned `FROM` lines and two
targets, not a second file that duplicates the build. The akmods image becomes
a stage (`AS nvidia-akmods`), and the variant target mounts its `/rpms` tree, as
the upstream recipe does [S9]. This keeps one copy of `build/common.sh`, and
Dependabot still sees both pins in one watched file.

## 2. Driver delivery: akmods versus prebuilt kmod

### The two mechanisms

| Mechanism | What the image carries | Verdict |
| --- | --- | --- |
| `akmod-nvidia` from negativo17/rpmfusion, compiled at image build | `kernel-devel`, the akmod source package, and a module built during the build | Not recommended. The build must compile the module itself, and an immutable image gains a compiler toolchain and kernel headers for no runtime benefit. Universal Blue builds this way in its own akmods image, not in the derived desktop image [S10]. |
| Prebuilt `kmod-nvidia` from `akmods-nvidia-open` | A signed `kmod-nvidia-<kernel>-<driver>` RPM and the userspace NVIDIA packages | **Recommended.** No compiler, no headers, and the module is built and signed once by the akmods pipeline [S10], [S11]. |

Universal Blue's `akmods` project publishes separate cached images per target:
`akmods` (common), `akmods-extra`, `akmods-nvidia`, `akmods-nvidia-open`, and
`akmods-zfs`, built daily for each supported kernel [S10]. The `nvidia-open`
target supports GeForce RTX 30 Series, which covers the RTX 3070; the closed
`nvidia` target exists for older hardware [S10]. The open driver is the correct
choice here.

### What the variant would install

`nvidia-install.sh` from the akmods image is the installer Universal Blue uses
[S9], [S11]. It:

- installs `ublue-os-nvidia-addons`, which writes the negativo17
  `fedora-nvidia` repository files [S12];
- installs the prebuilt `kmod-nvidia-${KERNEL_VERSION}-${NVIDIA_AKMOD_VERSION}`
  RPM from the mounted akmods tree, plus `nvidia-driver`,
  `nvidia-driver-libs`, `nvidia-driver-cuda`, `nvidia-kmod-common`,
  `nvidia-modprobe`, `nvidia-persistenced`, `nvidia-settings`, `egl-wayland`,
  `libva-nvidia-driver`, and `nvidia-container-toolkit` [S11], [S13];
- installs the 32-bit mesa and NVIDIA libraries on x86_64 so Steam and Vulkan
  work [S11];
- checks that the `kmod-nvidia` version equals the `nvidia-driver` version
  [S11];
- force-loads the module in the initramfs and preloads `i915 amdgpu nvidia`
  [S11].

The KMS requirement for Wayland is documented by NVIDIA: atomic modeset is
needed for non-X11 desktops, and the GBM backend needs DRM KMS, `libgbm`, and
`egl-wayland` 1.1.8 or later [S14], [S15]. That is why `egl-wayland` is in the
install list and why the kernel argument below matters.

### The kernel bump in an image that floats with Fedora

bootc upgrades are image upgrades: the new image is staged, the running system
is unchanged, and a reboot switches to it, with rollback available [S16]. The
kernel and the kmod travel inside the same image, so there is no host-side
akmod rebuild step and no race at boot. That is the main reason the prebuilt
kmod fits an immutable image.

The failure mode is at build time, not boot time. `nvidia-install.sh` takes
`KERNEL_VERSION` from the akmods image's `kmods/nvidia-vars` and checks the
module version against the driver version only [S11]. It does not compare that
kernel against the kernel the base image boots. If the two pins disagree, the
build can succeed while installing the module under
`/usr/lib/modules/<akmods-kernel>/extra/nvidia/`, which the booted kernel never
reads. The result is a green build and a machine that reaches the greeter with
no NVIDIA driver.

Three consequences:

1. Pin the akmods image by a kernel-specific tag **and** digest, not the
   floating `main-45` tag [S3].
2. Assert at build that the image's `kernel-core` release equals the module's
   directory, that `modinfo -k <release> nvidia` resolves, and that the module
   version equals the driver version. Fail closed.
3. Rebuild the initramfs after the install. `nvidia-install.sh` edits
   `/usr/lib/dracut/dracut.conf.d/99-nvidia.conf` but does not regenerate the
   initramfs [S11]; the upstream recipe runs `dracut --no-hostonly --add
   ostree` for the installed kernel and sets mode 0600 [S9].

A base digest bump therefore has to move both pins in one commit. That is a
review rule, not something Dependabot can infer from a single `FROM` line.

## 3. Kernel arguments and the iGPU

Recommendation: one new file, `overlay/usr/lib/bootc/kargs.d/30-nvidia.toml`,
next to the existing console and Plymouth files. bootc reads TOML files from
that directory, applies them at install, and applies changes from a later image
to the bootloader configuration while preserving machine-local arguments [S17].

| Argument | Why | Source |
| --- | --- | --- |
| `nvidia-drm.modeset=1` | Enables DRM kernel modesetting, which Wayland and the GBM backend require. NVIDIA's 620.70.06 README says KMS is enabled by default, so this pins the behaviour explicitly. | [S14], [S15] |
| `rd.driver.blacklist=nouveau` | Stops nouveau from claiming the RTX 3070 in the initramfs before the NVIDIA module loads. | [S18] |
| `modprobe.blacklist=nouveau` | Keeps nouveau from claiming it later in boot. | [S18] |
| `initcall_blacklist=simpledrm_platform_driver_init` | Optional. Aurora ships it to avoid the simpledrm-to-NVIDIA handover black screen. Gate it on a hardware test: without it the early console is more likely to stay visible, with it the panel may stay dark until the driver binds. | [S18] |

Do **not** add an `amdgpu` or `i915` blacklist. The akmods installer deliberately
preloads `i915 amdgpu nvidia` in the initramfs so a Chromium browser can use the
integrated GPU for acceleration [S11]. Removing the iGPU from the boot path
would remove the recovery display.

### The AMD iGPU and recovery

Two separate needs: keep `amdgpu` loaded so the iGPU remains a usable DRM
device, and give the operator a way to reach the machine when the NVIDIA driver
does not bind.

- Recovery console: the image already ships `console=ttyS0,115200`
  (`overlay/usr/lib/bootc/kargs.d/10-console.toml`). It is the recovery path
  when neither monitor lights.
- Console boot: append `systemd.unit=multi-user.target` at the bootloader to
  skip the graphical target. systemd documents `systemd.unit=` on the kernel
  command line [S19].
- Physical fallback: connect one monitor to an AMD iGPU output before relying on
  it. Whether the desktop's iGPU outputs are wired and enabled is unconfirmed.

### The Thunderbolt dock path

The design spec puts the Titan Ridge Thunderbolt bridge on the **laptop**, which
runs the generic variant, not on the desktop [S5]. The issue text pairs the AMD
iGPU with the dock path; on this repository's own hardware record those are two
different machines. Treat "dock displays depend on the NVIDIA driver" as
unconfirmed for the desktop until the dock model and its display path are
recorded in a hardware acceptance record, which the spec already requires [S5].
The generic variant is the one to test against the dock, and it is unaffected by
this plan.

## 4. Secure Boot

The premise in the issue, "third-party modules are unsigned", is only half
right. The akmods pipeline signs its modules with the Universal Blue key at
build [S10], [S20]. That key is not in a stock machine's firmware database, so
a Secure Boot machine refuses the module until the key is enrolled in MOK. The
common akmods addons package installs the key at
`/etc/pki/akmods/certs/akmods-ublue.der` for exactly that purpose [S12], and
Bluefin documents enrolling it with `ujust enroll-secure-boot-key` or
`mokutil --import`, followed by the reboot confirmation [S21].

With Secure Boot enabled and the key not enrolled:

- the kernel enforces module signature verification, so a module whose signing
  key it does not trust is refused [S22];
- `nvidia`, `nvidia-drm`, `nvidia-modeset`, `nvidia-uvm`, and `nvidia-peermem`
  never load, so no NVIDIA DRM device appears;
- Wayland cannot use the RTX 3070, and the two desktop monitors have no output
  from the compositor;
- the Fedora kernel itself is signed, so the machine still boots; only the
  third-party module is rejected.

What that means per machine:

| Machine | Secure Boot state | Consequence |
| --- | --- | --- |
| Desktop | Disabled today [S5] | The variant can be built and tested without MOK enrollment. Enabling Secure Boot later requires enrolling the Universal Blue key and completing the reboot prompt. |
| Laptop | Unknown [S5] | Not a target for this variant. Record the state before any NVIDIA work reaches it; the spec forbids disabling laptop Secure Boot to simplify a driver recipe [S5]. |

The variant must also install `ublue-os-akmods-addons` from the common `akmods`
image. `nvidia-install.sh` installs only `ublue-os-nvidia-addons`, and the MOK
key moved to the common addons package [S12]. Without it the key file is absent
and enrollment cannot be offered.

Test: boot the installed variant with Secure Boot on and the key **not**
enrolled. Expected: `dmesg` reports a module signature failure, `nvidia-smi`
fails, and the serial console still answers. Then enroll the key, reboot, and
assert `nvidia-smi` lists the RTX 3070. Both outcomes must be recorded before
claiming Secure Boot support.

## 5. Monitor topology loss until the driver loads

Both active desktop monitors are on the RTX 3070 [S5]. The NVIDIA driver is what
provides the DRM output for that GPU [S14]. Until `nvidia-drm` binds, there is
no compositor output on either monitor. This is an inference from those two
facts, not a boot observation.

What the operator loses, and for how long:

- From kernel start until `nvidia-drm` binds: no graphical output on the two
  monitors. The firmware framebuffer may keep one panel lit during this window;
  unconfirmed for this GPU and monitor combination.
- If the module is missing, refused by Secure Boot, or built for another kernel:
  the loss is permanent for that boot. The greeter and niri have no DRM output
  on the 3070, and the desktop is effectively headless.
- Recovery paths in that state: a monitor on an AMD iGPU output (unconfirmed
  wiring), the shipped serial console, or SSH if the network came up.

Test: boot the candidate qcow2 with `console=ttyS0,115200` and no GPU. Assert
the serial log reaches the greeter, `lsmod` shows `nvidia` loaded for the
running kernel, and `modinfo -k <release> nvidia` resolves. That proves the
module path, not the monitors. The monitor and dock assertions belong to the
physical acceptance record.

## 6. Package drift and issue #20

The lock is a post-build drift gate, not an install pin. `build/package-lock.sh`
reads only `manifests/packages-common.txt`, resolves each name in a built image,
and writes one `<nevra> TAB <vendor>` line; `tests/verify-image.sh` compares the
non-Fedora lines and fails on drift [S23], [S24]. Fedora lines float with the
updates repository on every build and are excluded [S8].

A variant manifest (`manifests/packages-nvidia.txt`) would be invisible to all
three pieces today:

- `build/package-lock.sh` hardcodes the common manifest path, so NVIDIA package
  names would never enter a lock;
- `tests/verify-image.sh` compares only `manifests/packages-common.lock`;
- `just lock` writes only that one file.

Minimum work: give the generator a manifest argument, add
`manifests/packages-nvidia.lock`, and teach `tests/verify-image.sh` which lock
belongs to the variant under test. Without that, the variant's NVIDIA userspace
is unpinned and a negativo17 rebuild changes the image silently.

Issue #20 already records the larger gap: the lock covers manifest names only,
so transitive packages are not gated, and the `%{VENDOR}` key is
package-controlled [S23], [S25]. The NVIDIA variant makes that gap wider,
because `nvidia-driver` pulls a large negativo17 userspace set and the 32-bit
libraries. The issue's own measurement counted 74 `negativo17.org` packages in
the generic image and 4 `ublue-os`; the variant adds to both [S25]. The kmod RPM's
vendor string is unconfirmed, so whether the drift gate would catch a rebuilt
`kmod-nvidia` line is unconfirmed until a built image is measured.

Do not put NVIDIA packages in `packages-common.txt`. That would install the
driver on the generic image, which the laptop does not need, and would make the
common lock kernel-dependent.

## 7. Ordered work breakdown

Each step names the test that proves it. Steps 1 to 7 are code work for a later
PR; this document does not perform them.

1. **Add the akmods pin and the variant target.** Add
   `FROM ghcr.io/ublue-os/akmods-nvidia-open:main-45-7.2.15-300.fc45@sha256:d08edbb4… AS nvidia-akmods`
   and two targets to `Containerfile`.
   **Proves:** a registry probe of both digests plus `podman build --target
   nvidia` succeeds; `podman build --target generic` still produces the current
   image.
2. **Teach the static gate the second pin.** Rewrite the base check in
   `tests/test-static.sh:17-27` so every `ghcr.io/ublue-os/` `FROM` must carry
   `@sha256:<64 hex>`, the base must still be `base-main:<major>`, and the
   akmods tag must carry the same Fedora major and a kernel-release suffix.
   **Proves:** `tests/lint.sh`; mutate one digest and one tag to prove the check
   goes red.
3. **Add `manifests/packages-nvidia.txt`, its lock, and the generator argument.**
   **Proves:** `tests/lint.sh` for the lock format and `tests/verify-image.sh`
   on the variant image for the third-party comparison. Mutate a locked NEVRA to
   prove the diff.
4. **Add `build/nvidia.sh`.** Mount the akmods `/rpms`, run `nvidia-install.sh`,
   install `ublue-os-akmods-addons`, rebuild the initramfs with `dracut
   --no-hostonly --add ostree`, and assert the kernel/module match.
   **Proves:** a new `tests/test-nvidia-match.sh` that fails on three fixtures:
   wrong module directory, `modinfo` miss, and driver/module version mismatch.
   It runs against a built image and is also called from `tests/verify-image.sh`.
5. **Add the kernel arguments.** New `overlay/usr/lib/bootc/kargs.d/30-nvidia.toml`
   with the table in section 3.
   **Proves:** a static assertion in `tests/test-static.sh` for the file's exact
   arguments, and the serial log of the VM boot showing the arguments applied.
6. **Add the variant to CI.** A matrix entry for the second target, its own
   artifact name, and a separate `publish`/`verify` path.
   **Proves:** `tests/lint.sh` (`actionlint` plus static assertions on the
   matrix), then a pull-request run that builds both targets.
7. **Boot the variant in a VM.** Reuse `tests/vm/boot-smoke.sh` with a variant
   parameter.
   **Proves:** the serial log reaches the greeter, `lsmod` and `modinfo` report
   the NVIDIA module for the running kernel, and `nvidia-smi` fails cleanly with
   no GPU. A no-GPU run proves module integrity only.
8. **Physical acceptance on the desktop.** Install to a spare disk, boot both
   monitors, record `nvidia-smi`, `drm_info`, the dock state, and a recovery
   boot with `systemd.unit=multi-user.target`. Record Secure Boot state before
   and after MOK enrollment.
   **Proves:** a hardware acceptance record under `docs/research/` with the
   commands and their output. No image claim lands before this record exists.
9. **Record the decision and the bump rule.** Update `README.md` status,
   `docs/build.md` (two pins, the kernel-match rule), `docs/known-gaps.md`, and
   `CHANGELOG.md`.
   **Proves:** `tests/lint.sh` ends `static checks passed`.

## Unconfirmed

- Whether the desktop's AMD iGPU has a wired, enabled output for a recovery
  monitor.
- Whether the Thunderbolt dock's display path touches the discrete GPU on the
  desktop; the design spec places the Thunderbolt bridge on the laptop.
- Whether the firmware framebuffer keeps one of the two monitors lit before
  `nvidia-drm` binds on this GPU.
- The `%{VENDOR}` string of the akmods-built `kmod-nvidia` RPM, and therefore
  whether the current drift gate would catch a rebuilt one.
- Whether Dependabot can be made to move both pins in one pull request; the
  kernel-match failure will surface either way.
- The exact driver behaviour on a 3070 with the open module under Fedora 45;
  only a physical boot can confirm it.
- The laptop's Secure Boot state and employer requirements.

## Sources

- [S1] ghcr.io manifest API, `ublue-os/base-main` tags `45` and the pinned
  digest `sha256:444e9e37…`, read 2026-11-12:
  `https://ghcr.io/v2/ublue-os/base-main/manifests/45` (image config labels
  `org.opencontainers.image.version`, `ostree.linux`).
- [S2] Repository base pin: `Containerfile:15`, `docs/build.md` (the literal
  `FROM` and the Dependabot rationale).
- [S3] ghcr.io manifest API, `ublue-os/akmods-nvidia-open` tags
  `main-45-7.2.15-300.fc45`, `main-45`, and their config labels
  (`ostree.linux`, `io.github.ublue-os.akmods.fingerprint-inputs`), read
  2026-11-12: `https://ghcr.io/v2/ublue-os/akmods-nvidia-open/manifests/main-45-7.2.15-300.fc45`.
- [S4] Universal Blue image-template README, "Adding NVIDIA drivers": the
  standalone `base-nvidia`, `silverblue-nvidia`, and `kinoite-nvidia` images
  are retired following ublue-os/main#927:
  `https://github.com/ublue-os/image-template/blob/main/README.md`;
  `https://github.com/ublue-os/main/issues/927`.
- [S5] Approved design,
  `docs/superpowers/specs/2026-11-09-dux-atomic-design.md`, hardware table
  (lines 73-74), Thunderbolt note (lines 77-78), and Secure Boot section
  (lines 345-348).
- [S6] `README.md:20`, the NVIDIA variant status row.
- [S7] `docs/build.md`, the literal pin and Dependabot's docker file matching.
- [S8] `docs/known-gaps.md`, the literal-`FROM` entry and the lock-scope entry
  (issue #20).
- [S9] Universal Blue image-template README, "Adding NVIDIA drivers", the
  `akmods-nvidia-open` stage, the `/rpms` mount, and the `nvidia-install.sh`
  plus `dracut` recipe:
  `https://github.com/ublue-os/image-template/blob/main/README.md`.
- [S10] Universal Blue akmods README, image groups (`common`, `extra`,
  `nvidia`, `nvidia-open`, `zfs`), per-kernel builds, the RTX 30 Series support
  entry, and the signing-key note:
  `https://github.com/ublue-os/akmods/blob/main/README.md`.
- [S11] `akmods/build_files/nvidia/nvidia-install.sh`, the install list, the
  kmod-versus-driver version check, the initramfs `force_drivers` and
  `i915 amdgpu nvidia` edits:
  `https://github.com/ublue-os/akmods/blob/main/build_files/nvidia/nvidia-install.sh`.
- [S12] `ublue-os-akmods-addons` spec, the MOK key at
  `/etc/pki/akmods/certs/akmods-ublue.der`:
  `https://github.com/ublue-os/akmods/blob/main/build_files/common/ublue-os-akmods-addons/ublue-os-akmods-addons.spec`;
  `ublue-os-nvidia-addons` spec, the negativo17 repo files:
  `https://github.com/ublue-os/akmods/blob/main/build_files/nvidia/ublue-os-nvidia-addons/ublue-os-nvidia-addons.spec`.
- [S13] `akmods/build_files/nvidia/download-nvidia-rpms.sh`, the userspace
  package names (`akmod-nvidia`, `nvidia-driver`, `nvidia-kmod-common`,
  `nvidia-modprobe`, `nvidia-persistenced`, `nvidia-settings`, 32-bit
  libraries):
  `https://github.com/ublue-os/akmods/blob/main/build_files/nvidia/download-nvidia-rpms.sh`.
- [S14] NVIDIA driver README 620.70.06, chapter 35 "Direct Rendering Manager
  Kernel Modesetting": atomic modeset for Wayland, `modeset` parameter, and
  KMS enabled by default:
  `https://download.nvidia.com/XFree86/Linux-x86_64/620.70.06/README/kms.html`.
- [S15] NVIDIA driver README 620.70.06, chapter 40 "GBM and GBM-based Wayland
  Compositors": DRM KMS, `libgbm`, and `egl-wayland` requirements:
  `https://download.nvidia.com/XFree86/Linux-x86_64/620.70.06/README/gbm.html`.
- [S16] bootc "Managing upgrades": staged image updates and rollback:
  `https://bootc-dev.github.io/bootc/bootc-upgrades.7.html`.
- [S17] bootc kernel-arguments manual, `/usr/lib/bootc/kargs.d` TOML and
  post-install application:
  `https://github.com/bootc-dev/bootc/blob/main/docs/src/building/bootc-kernel-arguments.7.md`.
- [S18] Universal Blue Aurora NVIDIA script, the `00-nvidia.toml` kernel
  arguments (`rd.driver.blacklist=nouveau`, `modprobe.blacklist=nouveau`,
  `nvidia-drm.modeset=1`, `initcall_blacklist=simpledrm_platform_driver_init`):
  `https://github.com/ublue-os/aurora/blob/main/build_scripts/base/04-nvidia.sh`.
- [S19] systemd kernel command line, `systemd.unit=`:
  `https://www.freedesktop.org/software/systemd/man/latest/kernel-command-line.html`.
- [S20] `akmods/build_files/post/dual-sign.sh`, module signing at build:
  `https://github.com/ublue-os/akmods/blob/main/build_files/post/dual-sign.sh`.
- [S21] Bluefin README, Secure Boot and `ujust enroll-secure-boot-key`:
  `https://github.com/ublue-os/bluefin/blob/main/README.md`.
- [S22] Linux kernel module signing facility, enforcement of module signatures
  and the effect of an untrusted key:
  `https://docs.kernel.org/admin-guide/module-signing.html`.
- [S23] `build/package-lock.sh`, `tests/verify-image.sh`, and `justfile` `lock`
  recipe: the manifest-name scope, the vendor filter, and the atomic write.
- [S24] `docs/build.md`, the lock as a post-build drift gate rather than an
  install pin.
- [S25] Issue #20, "Lock every third-party package, not only the manifest
  names": the 94-package third-party measurement and the `%{VENDOR}`
  limitation: `https://github.com/ultus-net/dux-atomic/issues/20`.
