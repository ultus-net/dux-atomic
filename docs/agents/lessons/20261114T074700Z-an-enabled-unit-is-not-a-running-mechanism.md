# L003 — an enabled unit is not a running mechanism

**Claim.** `systemctl is-enabled` says a unit is wanted, not that it runs. When a
mechanism is described as happening at boot, read the unit's `Condition*` and
`Exec*` lines before trusting it. On a bootc host, a unit guarded by
`ConditionPathExists=!/run/ostree-booted` never starts, and a unit that writes
under `/usr` could not succeed anyway, because a booted deployment mounts `/usr`
read-only.

**Applicability conditions.** Applies to any shipped service whose job writes
outside `/var`, and to any design that says a package "compiles", "generates", or
"enrolls" at first boot. Does not apply to units that only read state or write
under `/var`.

**Evidence.** The NVIDIA module path said `akmod-nvidia` compiles at first boot.
`/usr/lib/systemd/system/akmods.service:3` is
`ConditionPathExists=!/run/ostree-booted`, and `systemctl is-enabled
akmods.service` prints `enabled`. The image installs `ostree` and `bootc`, `/lib`
is a symlink to `usr/lib`, and `akmods@.service` is a kernel-transaction trigger
while `akmods-shutdown.service` is disabled. So the first-boot compile could
never run. Iteration 3 moved the compile into the image build
(`build/common.sh:77`, `build/build-nvidia-modules.sh`), and build 5 read the
five modules back out of the image. The decision and its revision are in
`docs/research/2026-11-14-nvidia-module-path-decision.md:22`.

**What this lesson does not license.** It does not prove that every akmod path
fails on every immutable host, and it does not say a package's own scripts are
wrong. It says a mechanism description must be checked against the unit that
would perform it, and that a build-time equivalent needs its own evidence.
