# NVIDIA module signing evidence (work item #72)

Commands run in the local dev image and on public repos, with verbatim output.

The commands below were run against the local dev image `localhost/dux-atomic:dev`.

1) Inspect the kmod-nvidia RPM (it contains no files)

Command:
podman run --rm localhost/dux-atomic:dev bash -lc 'cd /tmp && curl -sSLO https://negativo17.org/repos/multimedia/fedora-45/x86_64/kmod-nvidia-620.70.06-2.fc45.x86_64.rpm && ls -l kmod-nvidia-620.70.06-2.fc45.x86_64.rpm && rpm -qlp kmod-nvidia-620.70.06-2.fc45.x86_64.rpm'

Output:
-rw-r--r-- 1 root root 10009 Nov 14 00:56 kmod-nvidia-620.70.06-2.fc45.x86_64.rpm
(contains no files)

Finding: `kmod-nvidia` is not a kernel-module payload package here; it is a
small (10 KB) RPM with no installable files.

2) Show `kmod-nvidia`'s meaningful dependency (akmod-nvidia)

Command:
podman run --rm localhost/dux-atomic:dev bash -lc 'cd /tmp && curl -sSLO https://negativo17.org/repos/multimedia/fedora-45/x86_64/kmod-nvidia-620.70.06-2.fc45.x86_64.rpm && rpm -qpR kmod-nvidia-620.70.06-2.fc45.x86_64.rpm | grep -i akmod'

Output:
akmod-nvidia = 3:620.70.06-2.fc45

3) Inspect the akmod-nvidia RPM: it provides source artifacts, not a compiled
   module

Command:
podman run --rm localhost/dux-atomic:dev bash -lc 'cd /tmp && curl -sSLO https://negativo17.org/repos/multimedia/fedora-45/x86_64/akmod-nvidia-620.70.06-2.fc45.x86_64.rpm && rpm -qlp akmod-nvidia-620.70.06-2.fc45.x86_64.rpm'

Output:
/usr/src/akmods/nvidia-kmod-620.70.06-2.fc45.src.rpm
/usr/src/akmods/nvidia-kmod.latest

Finding: `akmod-nvidia` ships source/artifacts under /usr/src/akmods; the
compiled kmod is built on the host (akmods mechanism) at the first boot.

4) Confirm there is no kernel-specific prebuilt kmod package visible to dnf

Command:
podman run --rm localhost/dux-atomic:dev bash -lc "dnf5 repoquery --available --qf '%{name}-%{version}-%{release}.%{arch} %{repoid}\n' 'kmod-nvidia*'"

Output:
kmod-nvidia-620.70.06-2.fc45.x86_64 fedora-multimedia

Finding: the only `kmod-nvidia*` entry visible is the meta-package above; no
per-kernel kmod RPM was available from the enabled repositories.

5) Verify which userspace and 32-bit packages resolve (the manifest list)

Command:
podman run --rm localhost/dux-atomic:dev bash -lc "dnf5 repoquery --available --qf '%{name}-%{version}-%{release}.%{arch} %{repoid}\n' nvidia-driver nvidia-driver-libs nvidia-driver-cuda nvidia-modprobe nvidia-persistenced nvidia-settings nvidia-container-toolkit nvidia-driver-libs.i686 mesa-vulkan-drivers.i686 egl-wayland libva-nvidia-driver"

Output (decisive lines):
nvidia-driver-620.70.06-1.fc45.x86_64 fedora-multimedia
nvidia-driver-cuda-620.70.06-1.fc45.x86_64 fedora-multimedia
nvidia-driver-libs-620.70.06-1.fc45.x86_64 fedora-multimedia
nvidia-modprobe-620.70.06-1.fc45.x86_64 fedora-multimedia
nvidia-persistenced-620.70.06-1.fc45.x86_64 fedora-multimedia
nvidia-settings-620.70.06-1.fc45.x86_64 fedora-multimedia
mesa-vulkan-drivers-26.2.6-1.fc45.i686 fedora-multimedia
nvidia-driver-libs-620.70.06-1.fc45.i686 fedora-multimedia
egl-wayland-1.1.22-2.fc45.i686 fedora
libva-nvidia-driver-0.0.18-1.fc45.i686 fedora

Finding: `nvidia-container-toolkit` did not resolve in the enabled repos and was omitted from the manifest. The other userspace packages listed in the manifest resolve from negativo17/fedora-multimedia or Fedora as shown.

6) Secure Boot and module signatures

Reference: Linux kernel module signing facility — https://docs.kernel.org/admin-guide/module-signing.html

Plain consequence: on this image's configured repositories there is no vendor-signed prebuilt, kernel-specific kmod RPM available. The package layout here is a meta-package `kmod-nvidia` that requires `akmod-nvidia`, and `akmod-nvidia` ships source artifacts that the akmods build system compiles on the host at first boot. Therefore the choice is not an equal three-way split: either the operator accepts that akmod will compile modules on the host (unsigned until signed locally and enrolled), or the repository picture must change (a third party must publish per-kernel prebuilt kmod RPMs for the target kernel and that repo must be enabled and locked under the project's third-party rules).

What would restore a prebuilt option: a repository that publishes per-kernel kmod-nvidia-<kernel>-<driver>.rpm artifacts that include compiled module binaries and that is enabled in the image. No such prebuilt kmod was found in the enabled repositories when these commands ran.


7) What the enabled repositories actually allow

| Option | Available here | Cost | Per-machine step |
| --- | --- | --- | --- |
| Vendor-signed prebuilt kmod, pinned by NEVRA | No. No per-kernel kmod is published to the enabled repositories, and `kmod-nvidia` is an empty meta-package requiring `akmod-nvidia`. Restoring this path means enabling and locking a third-party repository that publishes per-kernel module RPMs. | Supply-chain trust in that repository, plus a repository decision under the repo's third-party rule. | None, if its signing key is trusted by the firmware. |
| akmod compiled on the host, signed locally, enrolled in MOK | Yes. `akmod-nvidia` is available from `fedora-multimedia`. | A compiler and kernel headers at first boot, a private signing key, and key custody. | One MOK enrollment per machine, no re-enrollment per kernel update while the same key signs the rebuild. |
| akmod with Secure Boot off on that machine | Yes, same package. | Weakens the boot chain on that machine. | Secure Boot disabled per machine. |

The RPM signature is package integrity, not a module signature:

Command:
podman run --rm localhost/dux-atomic:dev bash -lc 'cd /tmp && curl -sSLO https://negativo17.org/repos/multimedia/fedora-45/x86_64/akmod-nvidia-620.70.06-2.fc45.x86_64.rpm && rpm -Kv akmod-nvidia-620.70.06-2.fc45.x86_64.rpm'

Output:
akmod-nvidia-620.70.06-2.fc45.x86_64.rpm:
    Header OpenPGP V4 RSA/SHA512 signature, key fingerprint: 0c5d0f470484ae2fc40a9b6597f3008993e8909b: OK
    Header SHA256 digest: OK
    Payload SHA256 digest: OK

Recommendation (the decision stays with the operator):
Take the akmod path, because it is the only module path these repositories
provide. That means the variant needs `akmods`, `kernel-devel`, and a compiler
at first boot, plus a local signing key whose public half is enrolled in MOK on
each target, or Secure Boot off on that machine. The prebuilt path is the better
operating model if it ever becomes available, since it removes the on-host build
and the per-machine enrollment, but proposing it means naming the repository
that publishes per-kernel modules and accepting its trust.

## What this record does not prove

- That a compiled `nvidia.ko` carries a signature the kernel accepts.
  `modinfo -F signer` needs an installed module or a built image, and neither
  was produced here.
- That the akmod build succeeds on this kernel. It needs `kernel-devel` and a
  compiler at first boot, and this image ships neither today.
- That the variant boots on NVIDIA hardware with Secure Boot on or off. That is
  task 6's hardware step, and no Secure Boot claim is made before it.
- That the userspace packages install together cleanly. Only name resolution in
  the enabled repositories was measured.
