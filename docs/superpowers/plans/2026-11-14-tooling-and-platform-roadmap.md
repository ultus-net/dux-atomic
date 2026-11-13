# dux-atomic tooling and platform roadmap

Status: active. Supersedes the unstarted tasks in `2026-11-09-dux-atomic-candidate-images.md` and sequences the work after the Fedora bootc base swap (#59) and the developer tooling layer (#67).

> **For agentic workers:** one work item per task, one branch per work item, one PR that says `Fixes #<id>` in the same commit. Track steps with checkboxes. Read [Known gaps](../known-gaps.md) before starting a task it touches.

**Goal:** turn the current image into the system the design describes: a bootc workstation that is a sysadmin's first machine and a developer's second, with the tooling each layer owns, a promotion path that is honest about what CI can prove, and no unexplained gap between the shipped image and the dotfiles that configure it.

**Architecture:** four delivery layers, in this order of trust. The image carries root-owned and pre-login tools. Homebrew, installed by the dotfiles repository, carries user-space CLIs. A pinned rootless container carries the cloud SDKs and cluster tools. Flathub carries the GUI applications. Work lands as one work item per change, and promotion waits on hardware records rather than on a green build.

**Tech stack:** Fedora bootc 45, bash, podman or docker, bootc-image-builder, QEMU, GitHub Actions, cosign, syft, trivy.

**Spec:** [dux-atomic workstation design](../specs/2026-11-09-dux-atomic-design.md).

**Evidence:** [Developer and sysadmin tooling](../developer-tooling.md), [Applications](../applications.md), [Known gaps](../known-gaps.md), and the research records under `docs/research/`.

## Global constraints

- Never push to `main`. Branch prefixes are `feature/`, `fix/`, `chore/`, `docs/`, and `experiment/`.
- One work item per PR, `Fixes #<id>`, and one `CHANGELOG.md` entry in the same commit that closes it.
- Every manifest change regenerates `manifests/packages-common.lock` and the `image` job must be green.
- Prefer Fedora-signed packages. A third-party repository needs a stated reason, a vendor check, and a lock line; a new COPR needs an operator decision, not a default.
- The image ships no interactive user and no cloud SDK. Anything that needs a user login belongs to the dotfiles layer.
- Do not add a package the dotfiles already install: the split in [Developer and sysadmin tooling](../developer-tooling.md) is the contract.

## Where the repo stands

| Area | State | Evidence |
| --- | --- | --- |
| `main` | `8be8e62`, clean, three open work items before this roadmap (#4, #20, #67) | `git log -1` |
| Base image | Fedora `fedora-bootc:45`, digest-pinned, signed kernel asserted in CI | #59, #65 |
| Desktop | niri, DMS, greeter, Ghostty, Xfce fallback; first login provisions the DMS session | `docs/first-login.md` |
| Developer tooling | In review on `feature/dev-sysadmin-tooling`: compiler, Node 22 with npm, btop, diagnostics set, Node contract in `tests/verify-image.sh` | #67 |
| Gaming | Steam in the image; no game launched from a built image; Lutris not shipped | #69, `docs/known-gaps.md` |
| NVIDIA variant | Planned, not built; #40 planned it and closed | #70 |
| Agent isolation | Not built | #71 |
| Home snapshots | Not built | #72 |
| Publication | Signed digest, SBOM and provenance attested, `:latest` moves on manual promotion | #63, `docs/ci.md` |
| Secure Boot | Policy decided, no boot with it enabled recorded | `docs/known-gaps.md` |

## Order of work

The sequence is dependency order, not priority. Tasks 1 to 3 unblock an honest promotion; tasks 4 to 7 close the design's planned rows.

| # | Work item | Depends on | Done when |
| --- | --- | --- | --- |
| 1 | #67 Developer and sysadmin tooling | none | `image` job green, lock regenerated, PR merged |
| 2 | #68 Prove the dotfiles bootstrap | 1 | A booted image runs the dotfiles stage 20: npm globals install, `brew` starts, a distrobox container is created |
| 3 | #4 Containers signing policy | none | A shipped policy or a recorded release-key decision, with accept and reject fixtures |
| 4 | #20 Lock every third-party package | 1 | A transitive third-party rebuild reds the gate, not just a manifest name |
| 5 | #69 Gaming dogfood, then Lutris | hardware | One game launched from a built image, then Lutris shipped with an assertion |
| 6 | #70 NVIDIA variant | 5 | Its own digest-pinned `FROM`, a built digest, and a recorded akmod signing policy |
| 7 | #71 Project-scoped agent container | 2 | A scripted rootless profile with only the project mounted, and a test that reds on a forbidden mount |
| 8 | #72 Local home snapshots | a btrfs install | A btrbk config, an enabled timer, and a restore drill |
| 9 | Promotion gate | 3, 4, 5 | Secure Boot boot recorded on hardware, graphical dogfood recorded, `:latest` promoted |

## Task 1: land the developer tooling layer (#67)

Files: `manifests/packages-common.txt`, `manifests/packages-common.lock`, `tests/verify-image.sh`, `tests/test-static.sh`, `docs/developer-tooling.md`, `README.md`, `docs/applications.md`, `docs/known-gaps.md`, `CHANGELOG.md`.

- [x] Add the compiler, Node, and diagnostics groups to the manifest.
- [x] Add the Node and npm probes to `tests/verify-image.sh`, pinned by `tests/test-static.sh`.
- [x] Record the image, Homebrew, container, and Flathub split in `docs/developer-tooling.md`.
- [ ] Build the image and run `tests/verify-image.sh` against it.
- [ ] Regenerate `manifests/packages-common.lock`.
- [ ] Open the PR and wait for a green hosted `image` job.

Acceptance: the hosted `image` job is green, the lock carries the new Fedora NEVRAs, and the PR merges with `Fixes #67`.

## Task 2: prove the dotfiles bootstrap (#68)

Files: `tests/vm/boot-smoke.sh`, `docs/research/<date>-dotfiles-bootstrap.md`, `docs/developer-tooling.md`.

- [ ] Boot a built image and create a test account.
- [ ] Run the dotfiles `install/bootstrap.sh --only 20` as that account.
- [ ] Assert `npm ls -g` lists `opencode-ai`, `brew --version` answers, and `distrobox list` answers.
- [ ] Record the run and the exact package versions in a research file.

Acceptance: the dotfiles' own installer completes on this image without a manual fix, or the fix lands in the dotfiles repository and this item records the hand-off.

## Task 3: ship a containers signing policy (#4)

Files: `overlay/etc/containers/policy.json`, `tests/test-signing.sh`, `docs/known-gaps.md`, `CHANGELOG.md`.

- [ ] Decide the trust root: a release key referenced by `keyPath`, or a recorded decision to ship no policy.
- [ ] Write the policy and the rotation note.
- [ ] Extend `tests/test-signing.sh` with an accept and a reject against the shipped policy.

Acceptance: a host either verifies the image it pulls or the repository records why it cannot, with a test for whichever answer ships.

## Task 4: lock every third-party package (#20)

Files: `build/package-lock.sh`, `tests/verify-image.sh`, `tests/test-static.sh`, `docs/build.md`, `docs/known-gaps.md`.

- [ ] Enumerate transitive packages from a non-Fedora vendor, not only manifest names.
- [ ] Add a fixture proving a transitive rebuild reds the gate.
- [ ] Record the `+git` exception and the vendor-string limit in `docs/build.md`.

Acceptance: a rebuild of a package the manifest pulls in transitively fails the image job.

## Task 5: gaming dogfood, then Lutris (#69)

Files: `manifests/packages-common.txt`, `tests/verify-image.sh`, `docs/applications.md`, `docs/research/`.

- [ ] Launch one game from a built image on the gaming machine and record it.
- [ ] Add `lutris` to the gaming group only after the run passes.
- [ ] Assert `lutris` beside the Steam packages in `tests/verify-image.sh`.

Acceptance: the dogfood record exists and Lutris ships behind a green assertion, or the item closes with the failure finding.

## Task 6: build the NVIDIA variant (#70)

Files: `Containerfile.nvidia`, `manifests/packages-nvidia.txt`, `build/nvidia.sh`, `.github/workflows/ci.yml`, `tests/test-static.sh`, `docs/known-gaps.md`.

- [ ] Pin the variant `FROM` by tag and digest and extend the static gate to it.
- [ ] Decide the module path: a vendor-signed module from a repository, or a documented unsigned-module exception.
- [ ] Build the variant and publish it under its own tag.

Acceptance: the variant builds from its own pin, the module policy is recorded, and no Secure Boot claim is made until a boot is recorded.

## Task 7: project-scoped agent container (#71)

Files: `build/agent-run.sh`, `tests/test-agent-run.sh`, `docs/developer-tooling.md`.

- [ ] Write the `podman run` profile: the project mounted writable, a separate home and cache, no host home, SSH directory, agent socket, or Podman socket.
- [ ] Add a test that reds when any forbidden mount appears.
- [ ] Record a run on a built image.

Acceptance: an agent works in the container and the test proves the host surface stays out of it.

## Task 8: local home snapshots (#72)

Files: `overlay/etc/btrbk/btrbk.conf`, `overlay/usr/lib/systemd/system/btrbk.timer`, `tests/verify-image.sh`, `docs/install.md`.

- [ ] Write the btrbk configuration for the home subvolume.
- [ ] Enable the timer and assert it in the image job.
- [ ] Write and run the restore drill.

Acceptance: the timer is enabled, the config names the home subvolume, and the drill is recorded.

## Task 9: promotion gate

- [ ] Boot the promoted digest with Secure Boot enabled on each target and record `mokutil --sb-state`.
- [ ] Run the graphical dogfood on the promoted digest.
- [ ] Promote `:latest` and record the registry digests.

Acceptance: `docs/install.md` and `docs/known-gaps.md` state what the promoted digest was proven to do, and nothing more.

## Review focus

1. A tool shipped from a third-party repository without a lock line or vendor check. The gate must catch it, not a reviewer.
2. A Node or npm package that resolves but does not run. Task 1 pins the runtime probe, and Task 2 pins what the dotfiles do with it.
3. A signing policy that exists but cannot name this repository's keyless workflow. Task 3 records the limitation rather than papering over it.
4. A Secure Boot claim made from a VM boot without firmware. Task 9 requires hardware evidence.
5. A package added to both the image and the dotfiles. `docs/developer-tooling.md` is the split; a duplicate is a finding.

## Out of scope

- Hyprland, until each variant has a hardware acceptance record.
- Dotfiles changes. The `lazygit` and `yazi` gap and any `Brewfile` edit belong to that repository; this plan records the hand-off.
- Any change to the OpenCode fleet, skills, or agent configuration.
