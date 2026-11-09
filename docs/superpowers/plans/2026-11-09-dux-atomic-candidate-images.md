# dux-atomic candidate images implementation plan

Status: draft for operator review. No task in this plan is authorized until the design is approved.

> **For agentic workers:** use the `subagent-driven-development` or `executing-plans` skill. Track work with checkbox steps. One commit per task.

**Goal:** build and verify signed, bootable generic and NVIDIA candidate images with niri, DMS, Dux Greeter, and a minimal Xfce X11 session. Source from a digest-pinned ublue `base-main` Fedora 45 base. No host migration and no stable promotion in this phase.

**Architecture:** one shared `Containerfile` consumes two manifests and two build scripts, `common` and `nvidia`, over a pinned `ghcr.io/ublue-os/base-main:45@sha256:...` digest. CI builds both variants, signs candidate digests with cosign, and runs static and VM-boot tests. Gate 0 fixes the Dux Greeter X11 session-type defect with a tested minimal patch before any other work lands.

**Tech stack:** Podman or Containerfile, bash only, GitHub Actions, cosign, QEMU/KVM, and `bootc container lint`.

**Spec:** `docs/superpowers/specs/2026-11-09-dux-atomic-design.md`.

**Evidence:**

- `docs/research/2026-11-09-fedora-desktop-compatibility.md`
- `docs/research/2026-11-09-theme-version-audit.md`
- `docs/research/2026-11-09-omarchy-qol.md`

## Prerequisites

These are defined here and are not created by this plan.

- Initial commit on the current design branch, then a PR to `main`. The repository currently has no commits.
- `main` becomes protected. Only `feature/*`, `fix/*`, `chore/*`, and `experiment/*` branches build.
- Forge work items are created once the GitHub repository exists. Create one item per task. Do not create a remote repository or issues as part of this plan.
- No shared writable `.git` hooks or config across clones. Each clone configures hooks itself.
- Research uses the current Synthetic model. No OpenRouter calls.

## Global constraints

- Base: `ghcr.io/ublue-os/base-main:45`, pinned by digest and re-verified at execution with `skopeo inspect` plus a signature check. The digest in the compatibility report is an observation to re-confirm, not a trust anchor. **Pending: final pin values.**
- Shell, Containerfile, and configuration only. No Python, Go, or Ansible.
- No automatic reboot, wipe, rebase, or enrollment change. Updates stage only. The spec says no disk erase, rebase, enrollment change, or reboot is authorized by this document.
- Only candidate artifacts are published. Stable promotion waits for per-variant physical UAT records.
- No duplicate service stacks, SDK managers, or second shell or multiplexer. The dotfiles repository and OpenCode fleet remain untouched.
- Behavior tests assert runtime state in a booted VM: `loginctl`, `systemctl`, and `modinfo`. Configuration grep alone is not evidence.
- One commit per task with conventional verbs: `feat:`, `fix:`, `test:`, or `chore:`.
- Branch prefixes are `feature/` or `fix/`.

## Review focus

1. Xfce registers as `Type=wayland` under the unpatched greeter. A person logging into Xfce must get `loginctl` `Type=x11` and a working Xorg VT. Task 0 pins this with a VM test. A post-login wrapper must never be accepted as the fix.
2. NVIDIA kernel and module drift. The build must fail when the akmod target kernel differs from the image kernel. Task 3 pins this with a mismatch fixture.
3. An unsigned or wrong-key image is accepted by a built host. Task 5 pins this with a tamper test.
4. Inherited updater conflict. ublue's `rpm-ostreed-automatic.timer` and bootc apply units can reboot unattended. Task 2 pins this with `systemctl is-enabled` assertions in the VM.
5. Extra or wrong greeter entries. An Xfce Wayland entry or a duplicate niri entry must not appear. Task 4 pins this with session-entry assertions in the VM.

## File structure

| File | Responsibility |
| --- | --- |
| `Containerfile` | Single shared build. `ARG BASE_IMAGE`. Installs through `build/*.sh`. Builds both variants. |
| `manifests/packages-common.txt` | One package name per line. Comments group entries. No weak-dependency bloat from niri. |
| `manifests/packages-nvidia.txt` | NVIDIA-only packages, including akmods and 32-bit libraries. |
| `build/common.sh` | COPR enablement, DMS, greeter, niri, and Xfce X11 install. Updater-owner reconciliation and patch application. |
| `build/nvidia.sh` | NVIDIA layer plus the `assert_nvidia_match` kernel and module guard. |
| `patches/0001-dux-greeter-session-type.patch` | Minimal greeter fix with a provenance header. |
| `overlay/etc/containers/policy.json` | Host trust. Our registry scope pinned to our cosign identity. |
| `overlay/usr/lib/systemd/system/` | Masks and overrides for inherited updater units. |
| `tests/lib.sh` | Shared assertions such as `assert_eq` and VM helpers. |
| `tests/test-static.sh` | Shellcheck, digest-pin format, and manifest sanity. |
| `tests/test-greeter-session-type.sh` | Gate 0 VM test with fixture entries and serial-log assertions. |
| `tests/test-nvidia-match.sh` | Guard unit test with a mismatched fixture. |
| `tests/test-signing.sh` | Cosign accept and reject cases with a generated fixture keypair. |
| `tests/vm/make-disk.sh` | `bootc install to-disk` to a candidate qcow2. |
| `tests/vm/boot-assert.sh` | Boot the qcow2 and assert greeter, session, and updater runtime state. |
| `.github/workflows/build.yml` | Pull-request build of both variants, tests, signing, and candidate-only pushes. |

## Task 0: Gate 0, Dux Greeter X11 session-type fix

This task blocks every other task.

**Files:** create `patches/0001-dux-greeter-session-type.patch`, `tests/test-greeter-session-type.sh`, `tests/greeter-fixture/{xfce-x11,niri-wayland}.desktop`, and `tests/lib.sh`.

**Interfaces:** the patch is consumed by `build/common.sh` in Task 2. The fixture and assertion helpers are reused by Tasks 2, 4, and 6. A pass means `loginctl show-session <id> -p Type` returns `x11` for the Xfce fixture and `wayland` for niri, and the session environment captured to the serial console has the matching `$XDG_SESSION_TYPE`.

- [ ] **Step 1: Write the failing test.** Build a minimal test image from the pinned base digest with `greetd`, `dux-greeter` v2.1.2, and fixture entries whose `Exec` logs `loginctl show-session self -p Type` and `env` to `/dev/console`. Boot it with QEMU and assert `Type=x11` after selecting `xfce-x11.desktop`. Run `bash tests/test-greeter-session-type.sh`. Expected: FAIL with observed `Type=wayland`. This reproduces the finding on the real greeter, not by grep.
- [ ] **Step 2: Write the minimal patch.** Diff against dux-greeter v2.1.2 source. Derive `XDG_SESSION_TYPE` and `XDG_SESSION_DESKTOP` from the selected entry's session type. The header records upstream commit `c1e6a0352d56` and the test evidence.
- [ ] **Step 3: Open an upstream PR to `duxlabs-dev/dux-greeter`.** Record its URL in the patch header. **Pending: carry a local patch until merged, or hold the branch. The operator decides at review.**
- [ ] **Step 4: Rebuild with the patch and rerun the test.** Expected: PASS for both fixture entries. Verify greetd and PAM registration through `loginctl`, not an environment wrapper.
- [ ] **Step 5: Commit** `fix: greeter session-type patch with reproducing VM test`. Only the patch and test land here.

## Task 1: Repository skeleton, base pin, and static tests

**Files:** create `Containerfile` with the FROM pin and ARGs only, `manifests/packages-common.txt` as an empty stub, `tests/test-static.sh`, and a `CHANGELOG.md` entry.

**Interfaces:** the `BASE_IMAGE` argument format is `ghcr.io/ublue-os/base-main:45@sha256:<64hex>`. Every later build consumes it. `tests/lib.sh` comes from Task 0.

- [ ] **Step 1: Write the failing test.** Assert that the `Containerfile` FROM line matches the digest format and that the pinned digest exists on the registry. Run `skopeo inspect docker://ghcr.io/ublue-os/base-main:45`, compare, and fail on drift. Expected: FAIL because the file is missing.
- [ ] **Step 2: Implement the Containerfile skeleton** with the re-verified digest.
- [ ] **Step 3: Run** `bash tests/test-static.sh`. Expected: PASS.
- [ ] **Step 4: Commit** `feat: pin base-main fedora 45 digest with static test`.

## Task 2: Common desktop build

**Files:** create `build/common.sh`, fill `manifests/packages-common.txt`, and add masks or overrides under `overlay/usr/lib/systemd/system/`.

**Interfaces:** consumes the Task 0 patch and the Task 1 FROM pin. Produces a generic image with exactly two greeter-selectable sessions and one OS staging owner with reboot-on-apply disabled. **Pending: decide whether `rpm-ostreed` staging or bootc fetch-only owns updates. Check `bootc-updates(7)` and record the decision in the script header.**

- [ ] **Step 1: Extend `tests/vm/boot-assert.sh` and make it fail.** After `make-disk.sh` builds the generic image, assert that `systemctl is-enabled` reports the inherited timers as masked or absent, that both session files exist under `/usr/share/{xsessions,wayland-sessions}`, and that niri's weak-dependency lock and launcher stack is absent. Expected: FAIL.
- [ ] **Step 2: Implement `common.sh`.** Enable the Dux COPRs `duxlabs/dms` and `duxlabs/dux-repo`. Install pinned DMS 2.1.2 and the patched greeter. Install Quickshell 0.3.x from COPR because Fedora's 0.2.1 snapshot lacks the AppId pragma. Install niri with `--setopt=install_weak_deps=False`. Install the explicit Xfce X11 set: Xorg, xinit, window manager, panel, lock, power, and portal. Install Ghostty. Apply the updater masks. Record package origins and COPR trust notes in the script header. **Pending: choose the COPR version pinning mechanism, vendored RPMs or version lock, using live COPR evidence.**
- [ ] **Step 3: Build the generic variant with `podman build` and run the VM assertions.** Expected: PASS.
- [ ] **Step 4: Commit** `feat: common desktop build with single update owner`.

## Task 3: NVIDIA variant with kernel and module guard

**Files:** create `build/nvidia.sh`, `manifests/packages-nvidia.txt`, and `tests/test-nvidia-match.sh`. Add `ARG NVIDIA=false` to the `Containerfile`.

**Interfaces:** `assert_nvidia_match <kernel-release> <module-version>` exits non-zero on disagreement. The build fails if versions disagree. Consumes the Task 2 build.

- [ ] **Step 1: Write the failing test with fixtures.** Create two fixture trees with a fake kernel release and fake `modinfo` output. One pair matches. The drifted pair must exit non-zero. Expected: FAIL because the function is missing.
- [ ] **Step 2: Implement `nvidia.sh`.** Install the akmod stack. Run the guard against the image kernel release from `rpm -q kernel` and the built initramfs module path. Assert the built `.ko` version with `modinfo` inside the image. No GPU is required.
- [ ] **Step 3: Run** `test-nvidia-match.sh` and a full NVIDIA build. Expected: PASS for both. Record a negative run where the versions are forced apart.
- [ ] **Step 4: Commit** `feat: nvidia variant with kernel module version guard`.

## Task 4: Session separation and Xfce ownership

**Files:** modify `build/common.sh` for per-session portal and environment configuration. Add session-entry fixes under `overlay/`. Extend `tests/vm/boot-assert.sh`.

**Interfaces:** assert in the booted VM that there is exactly one Xfce X11 entry, no Xfce Wayland entry, and no duplicate niri entry. Assert that `xfce4-notifyd` D-Bus activation remains intact in both sessions. Assert that DMS and niri user services are absent from the Xfce session's `systemctl --user` list.

- [ ] **Step 1: Extend the VM assertions and make them fail.** Expected: FAIL.
- [ ] **Step 2: Implement per-session portal configuration and entry fixes** under `overlay/` and `common.sh`.
- [ ] **Step 3: Rerun the VM assertions on the generic image.** Expected: PASS.
- [ ] **Step 4: Commit** `feat: session separation for xfce x11 fallback`.

## Task 5: Signing, host trust policy, and CI candidate publishing

**Files:** create `tests/test-signing.sh`, `.github/workflows/build.yml`, and `overlay/etc/containers/policy.json`.

**Interfaces:** CI signs candidate digests such as `ghcr.io/<owner>/dux-atomic[-nvidia]:candidate-<sha>` with a cosign key stored only in CI secrets. `policy.json` pins our registry scope to our public-key identity. This workflow never pushes a stable tag.

- [ ] **Step 1: Write the failing test** with a locally generated fixture keypair. A signed fixture artifact must pass. Unsigned and wrong-key artifacts must be rejected. Expected: FAIL because the script is missing.
- [ ] **Step 2: Implement the test and workflow.** Build both variants, run the Task 0 to Task 4 tests, run `bootc container lint`, sign, and push candidates. Add the signing rotation bootstrap runbook as documentation in this task. Key generation, rotation, and re-trust execution remain operator-owned. **Pending: rotation procedure approval.**
- [ ] **Step 3: Run** `bash tests/test-signing.sh`, open a PR, and confirm the workflow publishes signed candidates. Expected: PASS.
- [ ] **Step 4: Commit** `feat: cosign candidate signing with host trust policy`.

## Task 6: Full VM boot acceptance for both variants

**Files:** extend `tests/vm/make-disk.sh` and `tests/vm/boot-assert.sh` to take a variant parameter.

**Interfaces:** final gate for deliverable 1. Each candidate qcow2 boots to Dux Greeter. The niri session reaches a Wayland session with `Type=wayland`. The Xfce session reaches `Type=x11` on Xorg. No update unit triggers an automatic reboot. A TTY recovery path is documented in `README.md`.

- [ ] **Step 1: Write the failing end-to-end assertion script.** Cover the five review-focus states in one boot per variant. Expected: FAIL while any gap remains.
- [ ] **Step 2: Fix gaps found.** Any new gap beyond Tasks 0 to 4 becomes a work item, not a silent patch.
- [ ] **Step 3: Run both variants end to end.** Expected: PASS. Record the digests in `CHANGELOG.md`.
- [ ] **Step 4: Commit** `test: vm boot acceptance for both candidate variants`.

## Approved QoL additions

These were approved after the first plan draft. They are downstream work and must not expand deliverable 1 without a separate plan.

- Staged-update visibility with an explicit reboot action.
- NVIDIA suspend, resume, and hibernate hooks with a tested power transition.
- Per-device power and display profiles keyed to dock and monitor identity.
- Per-device audio defaults, microphone noise suppression, and Bluetooth codec preference.
- Notification and clipboard discipline, including secret exclusion and one notification daemon.
- Offline recovery and diagnostics, including a redacted bundle.

Each item gets a work item, an owner, and an acceptance test. Ownership splits between image and dotfiles so nothing is installed twice.

| Item | Image responsibility | Dotfiles responsibility |
| --- | --- | --- |
| Staged update visibility | Update state and staging service | DMS indicator and explicit reboot action |
| NVIDIA suspend and resume | Services and hooks | Verification notes and recovery shortcut |
| Per-device power and display | udev rules and niri output defaults | Personal profiles and scale presets |
| Audio state | WirePlumber and codec packages | Per-device defaults and suppression configuration |
| Notification and clipboard | Daemons and portal integration | Do-not-disturb rules, history, and secret exclusion |
| Offline recovery | Recovery documentation and diagnostics script | Links, issue template, and runbook |

## Downstream phases

Each phase gets its own plan and work items.

- **Dotfiles profile.** Add a `dux-atomic` package profile. Reconcile bootstrap and Brewfile ownership. Decide whether OpenCode ships natively or at user level. Define defaults-before-dotfiles ordering so image defaults never compete with dotfiles paths. Excluded: changing existing machine profiles or touching `feature/hermes-standards-adoption`.
- **Role-focused QoL.** The image owns Podman, portals, diagnostics, and system defaults. Dotfiles own the pinned operations container, project templates, onboarding, learning aids, and the local cluster helper. Excluded: cloud CLIs in the host image, a second SDK manager, and passwordless sudo.
- **Agent runner.** Build an isolated rootless Podman project clone with read-only image configuration, scoped credentials, and offline and online profiles. Excluded: Distrobox as the restricted runner and tailnet ACL changes.
- **Theme adapter.** Build an Omarchy palette to DMS custom-theme JSON importer. Verify Zed and Ghostty template output. Excluded: porting the Omarchy manager, shipping Aether, and redistributing wallpapers without licence checks.
- **Snapshots, Flatpaks, and applications.** Add btrbk with LUKS and btrfs layout validation. Create a Flatpak manifest with verified IDs. Excluded: enabling snapshots before layout validation.
- **Migration.** Require an external backup and explicit operator confirmation. The desktop needs a tested atomic install path from Arch to bootc. NVIDIA UAT uses a spare disk. Never wipe the running Omarchy installation.

## Reviewer findings carried forward

- No shared writable `.git` hooks or config across agent clones.
- Base digest bumps follow a scheduled re-pin with security review. A base-major change reruns every task and requires package, kernel, service, and hardware revalidation.
- NVIDIA physical UAT requires a spare-disk install. A no-GPU CI run proves kernel and module integrity only.
- The LUKS and btrfs snapshot layout is a downstream gate. No snapshot unit ships in deliverable 1.
- Defaults ownership ordering is resolved in the dotfiles phase. Image defaults in this phase stay minimal.

Pending decisions are labeled inline. An executor must not resolve one silently. Record every resolution in `CHANGELOG.md`.
