# NVIDIA variant build evidence (work item #72)

Status: measurement record. Cutoff 2026-11-14. This record builds the variant
locally and reads the installed set back out of the image. It does not boot the
image on NVIDIA hardware or make a Secure Boot claim. The sections before the
compile read the manifest and kernel wiring from an earlier build; the compile
section records build 5 (image `c4fd38cddb70`).

## Question

The variant's manifest named its userspace stack but nothing that could build
the module. `build/common.sh` read only `manifests/packages-common.txt`, so
`Containerfile.nvidia` installed no variant package at all. This record answers
two questions: does the wiring install the variant set, and do the kernel
headers the akmod needs belong to the kernel the image boots?

## The build

Command:

```
podman build --layers -t localhost/dux-atomic:nvidia -f Containerfile.nvidia .
```

Output (last lines):

```
Checks passed: 12
Checks skipped: 1
Warnings: 2
[2/2] COMMIT localhost/dux-atomic:nvidia
--> aae9510831b0
Successfully tagged localhost/dux-atomic:nvidia
aae9510831b05033b4cc53b8686b3bfde3ee7cf77ad7f6384d36f0f9f39ae488
```

Exit status 0. The two `bootc container lint` warnings are the `/var` content
and tmpfiles notes this base already produces; the build does not gate on them.

## The extra manifest installs

`build/common.sh` logs the command it runs for each manifest. The variant's
install is the second one, after the shared set. `build/check-manifest-name.sh`
turns the `PACKAGE_MANIFEST_EXTRA` value into the path first, so a slash or an
empty value fails the build instead of reading another file in the context:

```
+ dnf5 install -y nvidia-driver nvidia-driver-libs nvidia-driver-cuda nvidia-modprobe nvidia-persistenced nvidia-settings egl-wayland libva-nvidia-driver akmod-nvidia akmods kernel-devel-matched gcc make mesa-vulkan-drivers.i686 nvidia-driver-libs.i686
```

Read back from the image:

```
$ podman run --rm localhost/dux-atomic:nvidia bash -lc 'for n in ...; do rpm -q --whatprovides "$n"; done'

nvidia-driver: nvidia-driver-620.70.06-1.fc45.x86_64
nvidia-driver-libs: nvidia-driver-libs-620.70.06-1.fc45.x86_64 nvidia-driver-libs-620.70.06-1.fc45.i686
nvidia-driver-cuda: nvidia-driver-cuda-620.70.06-1.fc45.x86_64
nvidia-modprobe: nvidia-modprobe-620.70.06-1.fc45.x86_64
akmod-nvidia: akmod-nvidia-620.70.06-2.fc45.x86_64
akmods: akmods-0.6.2-14.fc45.noarch
kernel-devel-matched: kernel-devel-matched-7.3.3-300.fc45.x86_64
gcc: gcc-16.2.1-3.fc45.x86_64
make: make-4.4.1-13.fc45.x86_64
```

The source package the akmod compiles is present:

```
$ podman run --rm localhost/dux-atomic:nvidia ls /usr/src/akmods
nvidia-kmod-620.70.06-2.fc45.src.rpm
nvidia-kmod.latest
```

## The headers match the kernel

```
$ podman run --rm localhost/dux-atomic:nvidia rpm -q kernel kernel-core kernel-devel kernel-devel-matched
kernel-7.3.3-300.fc45.x86_64
kernel-core-7.3.3-300.fc45.x86_64
kernel-devel-7.3.3-300.fc45.x86_64
kernel-devel-matched-7.3.3-300.fc45.x86_64

$ podman run --rm localhost/dux-atomic:nvidia rpm -qR kernel-devel-matched
kernel-core = 7.3.3-300.fc45
kernel-devel = 7.3.3-300.fc45
rpmlib(CompressedFileNames) <= 3.0.4-1
rpmlib(FileDigests) <= 4.6.0-1
rpmlib(PayloadFilesHavePrefix) <= 4.0-1
rpmlib(PayloadIsXz) <= 5.2-1
```

`kernel-devel-matched` is a 0-byte meta-package. `rpm -qR` above shows the two
requirements it carries: `kernel-devel` and `kernel-core`, both at its own
version. That pins the pair to one version. The package does not consult the
installed kernel. The four equal versions above are the result here because the
`updates` repository's newest kernel is also the pinned base's kernel on this
date, so this build cannot separate the two mechanisms.

A later base that lags `updates` is the case the name would not catch, so
`build/common.sh` runs `build/check-kernel-devel.sh` when `kernel-devel` is
installed:

```
+ bash /ctx/build/check-kernel-devel.sh 7.3.3-300.fc45.x86_64 7.3.3-300.fc45.x86_64
```

The check fails the build unless one installed `kernel-devel` equals the newest
installed kernel. Its green, mismatched, and empty-set paths are exercised by
`tests/test-static.sh`.

## The akmod compiles during the image build

The first attempt at this path said the akmod compiles on first boot. The image
rules that out before any boot. `akmods.service` carries
`ConditionPathExists=!/run/ostree-booted` and is enabled, and a bootc host is
ostree-booted. `/lib` is also a symlink to `usr/lib`, and a booted deployment
mounts `/usr` read-only, so the write would fail even without the unit
condition. `akmods@.service` is a kernel-transaction trigger and
`akmods-shutdown.service` is disabled, so neither reaches a first boot.

The compile therefore runs in `build/common.sh` through
`build/build-nvidia-modules.sh`, guarded on an installed `akmod-nvidia`:

```
+ rpm -q akmod-nvidia
+ bash /ctx/build/build-nvidia-modules.sh
Checking kmods exist for 7.3.3-300.fc45.x86_64 [  OK  ]
Building and installing nvidia-kmod [  OK  ]
```

A probe in a container of the earlier variant image established the compile
separately and measured it: `akmods --force --kernels 7.3.3-300.fc45.x86_64`
exited 0 in 1:09.45 and produced the five modules with no signer. Build 5 then
ran the same path inside `podman build --layers -t localhost/dux-atomic:nvidia
-f Containerfile.nvidia .`, which exited 0 after 28m47s and committed image
`c4fd38cddb70` (digest
`sha256:51e8dc13ac74ba2f325df29578b4da8c60452d8aa94c55f2850d4c75bbb6886d`).
`bootc container lint` reported `Checks passed: 12`, `Checks skipped: 1`,
`Warnings: 2`, the same counts as build 4.

Read back from build 5:

```
$ podman run --rm localhost/dux-atomic:nvidia find /lib/modules -path '*extra/nvidia*' -name '*.ko*' -print
/lib/modules/7.3.3-300.fc45.x86_64/extra/nvidia/nvidia-drm.ko.xz
/lib/modules/7.3.3-300.fc45.x86_64/extra/nvidia/nvidia-modeset.ko.xz
/lib/modules/7.3.3-300.fc45.x86_64/extra/nvidia/nvidia-peermem.ko.xz
/lib/modules/7.3.3-300.fc45.x86_64/extra/nvidia/nvidia-uvm.ko.xz
/lib/modules/7.3.3-300.fc45.x86_64/extra/nvidia/nvidia.ko.xz
```

```
nvidia signer=[] version=[620.70.06] owner=[kmod-nvidia-7.3.3-300.fc45.x86_64-620.70.06-2.fc45.x86_64]
nvidia-uvm signer=[] version=[620.70.06] owner=[kmod-nvidia-7.3.3-300.fc45.x86_64-620.70.06-2.fc45.x86_64]
nvidia-drm signer=[] version=[620.70.06] owner=[kmod-nvidia-7.3.3-300.fc45.x86_64-620.70.06-2.fc45.x86_64]
nvidia-modeset signer=[] version=[620.70.06] owner=[kmod-nvidia-7.3.3-300.fc45.x86_64-620.70.06-2.fc45.x86_64]
nvidia-peermem signer=[] version=[620.70.06] owner=[kmod-nvidia-7.3.3-300.fc45.x86_64-620.70.06-2.fc45.x86_64]
vermagic=[7.3.3-300.fc45.x86_64 SMP preempt mod_unload]
```

The akmod's RPM owns every module, so the build installed them rather than
leaving unowned files under `/usr`. The directory is 13 MB. Every module has an
empty signer, which is the documented exception and not a surprise: the build
does not generate or enroll a key.

## What this record does not prove

- No boot on NVIDIA hardware, with Secure Boot off or on. The modules are
  unsigned, so a Secure Boot machine refuses them until a local MOK enrollment
  (#40).
- The check compares the newest installed kernel with the installed devel. It
  does not prove the image carries exactly one kernel, and a two-kernel image
  with the older one booting would pass it.
- The variant is not built in CI and has no lock file, so a rebuild can differ
  from this digest when a repository moves.
