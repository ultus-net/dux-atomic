# L002 — a package name that promises a property is not a check of that property

**Claim.** When a dependency's name states a guarantee (`-matched`, `-latest`,
`-compat`, `uname-r`), the guarantee is the package's own version relation, not
a lookup against the system it lands on. Read `rpm -qR` before relying on the
name. Where the property matters, assert it at the point where both sides are
readable, and fail the build.

**Applicability conditions.** Applies when a package, module, or flag name
encodes a relationship to something else on the machine. Does not apply to a
name that only states its content.

**Evidence.** Iteration 2 added `kernel-devel-matched` to
`manifests/packages-nvidia.txt` with the claim that it "pulls the kernel-devel
for the installed kernel rather than the newest in the repository". The build
installed `kernel-devel-matched-7.3.3-300.fc45` from `updates`, and
`rpm -qR kernel-devel-matched` shows `kernel-core = 7.3.3-300.fc45` and
`kernel-devel = 7.3.3-300.fc45`: it pins its own version, not the installed
kernel. It matched because the pinned base's kernel is also 7.3.3-300.fc45, so
the build could not tell the two mechanisms apart. Commit `3500e54` adds
`build/check-kernel-devel.sh`, which fails the build unless an installed
`kernel-devel` equals the newest installed kernel; `tests/test-static.sh`
exercises its green, mismatched, and empty-set paths. The corrected comment is
in `manifests/packages-nvidia.txt:27-32`, and the measurement is
`docs/research/2026-11-14-nvidia-variant-build.md`.

**What this lesson does not license.** A build-time version check does not
prove the akmod compiles at boot. It compares the newest installed kernel with
the devel package, not `uname -r` of the booted kernel, and a two-kernel image
with the older one booting would pass it.
