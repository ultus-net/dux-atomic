# Headless Server Image, Part 1: Base Split and Image Definition

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `ultus-atomic-server` as a third published-candidate image whose base carries no desktop, no gaming, and no developer toolchain, and prove the desktop image still installs exactly what it did.

**Architecture:** File-per-host, the pattern `Containerfile.nvidia` already uses. Each Containerfile copies one module tree by name, so a host cannot inherit another host's module. `packages-common.txt` becomes the server-safe base; desktop-only groups move to `packages-desktop.txt`, which the desktop module hook already installs. The server module starts with one unit, the data-disk mount, so this part ends with a bootable server image that mounts `/var/srv` and carries nothing else.

**Tech Stack:** Fedora 45 `fedora-bootc` base pinned by tag and digest, `dnf5`, systemd units, bash gates in `tests/`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-20-headless-server-image-design.md` (revision 2, approved 2026-11-20)

## Global Constraints

- One base pin: every `Containerfile*` carries the identical `FROM registry.fedoraproject.org/fedora-bootc:45@sha256:...` digest.
- Fedora packages first. The only third-party package sources stay the duxlabs COPRs and RPM Fusion.
- No secret, key, or credential enters the image, the build log, or the repository.
- The data disk mounts by `LABEL=ultus-data` at `/var/srv`, never at `/srv`, because `/srv` is a symlink in the base image.
- The static gate (`tests/test-static.sh`) stays the cheapest gate and runs before any image builds.
- Every write path ships off by default. No unit in this part writes to a disk.
- `manifests/packages-common.lock` must stay byte-identical through the split, because moving a package between manifests does not change what the desktop installs.

## Review Focus

These are the input classes and failure modes the spec implies but no unit test in this part exercises. Each has its test in the task that owns the code.

1. A desktop group left behind in `packages-common.txt`: the server image ships Steam or an X server. The server verifier fails on any installed name from `packages-desktop.txt`.
2. A group moved twice or lost: the desktop image quietly loses a package. The desktop check compares `rpm -qa` against the old set plus `tailscale`.
3. `tailscale` resolves from a different repository than the one measured. Every image verifier asserts `rpm -q tailscale` so a base or repo bump reds instead of silently dropping it.
4. `Containerfile.server` omits a build-context tree, so `build/common.sh` skips a step and still exits 0. The ctx-tree comparison loops over every `Containerfile*`.
5. The repin workflow rewrites two Containerfiles and strands the third on an older base. A static assertion compares the base digest across all of them.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `manifests/packages-common.txt` | Server-safe base package set, installed by every image |
| `manifests/packages-desktop.txt` | Desktop session, compositor, gaming, toolchain; installed by the desktop hook only |
| `manifests/packages-server.txt` | Server host tools, installed only by the server variant |
| `build/common.sh` | Shared build; loses the Flathub seed, keeps RPM Fusion and the manifest installer |
| `modules/desktop/usr/libexec/ultus-atomic/build.d/50-desktop.sh` | Desktop build step; gains the Flathub seed |
| `Containerfile`, `Containerfile.nvidia`, `Containerfile.server` | One host each; each copies one module tree |
| `modules/server/usr/lib/systemd/system/var-srv.mount` | The server's only behaviour in this part |
| `tests/test-static.sh` | Base pin, module copy, one-base digest, manifest role assertions |
| `tests/verify-image.sh` | Role-aware image assertions and per-image lock |
| `.github/workflows/repin-base.yml` | Rewrites every Containerfile |
| `.github/workflows/ci.yml` | `server` path filter and a server build-and-verify job |

---

### Task 1: Split the package manifests

**Files:**
- Modify: `manifests/packages-common.txt`
- Modify: `manifests/packages-desktop.txt`
- Create: `manifests/packages-server.txt`
- Modify: `build/common.sh:73-77`
- Modify: `modules/desktop/usr/libexec/ultus-atomic/build.d/50-desktop.sh`
- Modify: `tests/test-static.sh:53`, `tests/test-static.sh:262-271`
- Test: `tests/test-static.sh`
- Docs: `CHANGELOG.md`, `docs/build.md`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `manifests/packages-server.txt` exists and holds `restic`. `packages-common.txt` holds `tailscale` and holds no name from `packages-desktop.txt`. The desktop hook installs the Flathub remote.

- [ ] **Step 1: Write the failing role assertions in `tests/test-static.sh`**

Add after the existing `packages-common.txt` one-package-per-line block:

```bash
# The server image installs packages-common.txt plus packages-server.txt. A
# desktop package left in the base ships Steam and an X server to a headless
# box, so name the failure here rather than in an image build.
server_manifest=$repo_root/manifests/packages-server.txt
desktop_manifest_early=$repo_root/manifests/packages-desktop.txt
overlap=$(grep -Ev '^[[:space:]]*(#.*)?$' "$desktop_manifest_early" |
  while read -r name; do grep -qx "$name" "$repo_root/manifests/packages-common.txt" && echo "$name"; done)
if [[ ! -f $server_manifest ]]; then
  echo "FAIL manifests/packages-server.txt is missing" >&2
  failures=$((failures + 1))
elif [[ -n $overlap ]]; then
  echo "FAIL packages-common.txt still names desktop packages:"$'\n'"$overlap" >&2
  failures=$((failures + 1))
elif ! grep -qx 'tailscale' "$repo_root/manifests/packages-common.txt"; then
  echo "FAIL packages-common.txt does not name tailscale, so the server ships no tailnet" >&2
  failures=$((failures + 1))
elif ! grep -qx 'restic' "$server_manifest"; then
  echo "FAIL packages-server.txt does not name restic" >&2
  failures=$((failures + 1))
else
  echo "ok   the base names tailscale and no desktop package, and the server names restic"
fi
```

- [ ] **Step 2: Run the static gate to verify it fails**

Run: `tests/test-static.sh`
Expected: FAIL with `manifests/packages-server.txt is missing`.

- [ ] **Step 3: Move the desktop groups out of the base**

Cut these names from `manifests/packages-common.txt` and append them under their existing group comments in `manifests/packages-desktop.txt`:

- The whole portal/keyring/policy block: `xdg-desktop-portal`, `xdg-desktop-portal-gtk`, `xdg-desktop-portal-gnome`, `gnome-keyring`, `xfce-polkit`, `accountsservice`, `upower`, `rtkit`, `playerctl`, `xdg-user-dirs`, `xdg-utils`, `dconf`, `hicolor-icon-theme`, `adwaita-icon-theme`, `adwaita-cursor-theme`.
- The audio block: `pipewire`, `pipewire-alsa`, `pipewire-pulseaudio`, `pipewire-utils`, `wireplumber`, `alsa-utils`, `alsa-ucm`, `alsa-sof-firmware`.
- From the hardware block: `bluez`, `power-profiles-daemon`, `brightnessctl`. Keep `NetworkManager-wifi`, `wpa_supplicant`, and `iwlwifi-mvm-firmware` in the base, because either host may join a wireless network.
- The graphics and codec block: `mesa-dri-drivers`, `mesa-vulkan-drivers`, `vulkan-loader`, `xwayland-satellite`, `xorg-x11-server-Xwayland`, `libva-intel-media-driver`, `gstreamer1-plugins-good`, `gstreamer1-plugin-libav`, `ffmpeg`, `google-noto-color-emoji-fonts`.
- From the terminal/container block: `distrobox`, `wl-clipboard`, `flatpak`.
- The whole build toolchain block: `gcc`, `gcc-c++`, `make`, `patch`, `zlib-ng-compat-devel`, `bzip2-devel`, `nodejs`, `nodejs-npm`.
- The Xfce fallback block: `xfce4-session`, `xfwm4`, `xfce4-panel`, `xfce4-screensaver`, `xfce4-power-manager`, `xfce4-notifyd`, `xorg-x11-server-Xorg`, `xinit`.
- The gaming block: `steam`, `gamescope`, `mangohud`, `steam-devices`.

Keep in the base: `firewalld`, `zram-generator-defaults`, `tmux`, `htop`, `btop`, `git`, `just`, `fzf`, `rsync`, `zip`, and the whole sysadmin diagnostics block. Add `tailscale` to the base under a new comment `# Tailnet: every host joins, the server is reachable only through it`.

In `packages-desktop.txt`, keep the existing header and rename the first group comment to `# Session services, compositor, shell, greeter and terminal`, keeping every existing name.

- [ ] **Step 4: Create `manifests/packages-server.txt`**

```text
# packages-server.txt — host tools the server needs and no other role does.
# Installed only by Containerfile.server through PACKAGE_MANIFEST_EXTRA.

restic
```

- [ ] **Step 5: Move the Flathub seed into the desktop hook**

Delete `build/common.sh` lines 73-77 (the `install -d /etc/flatpak/remotes.d` block and its comment). Add the same block to `modules/desktop/usr/libexec/ultus-atomic/build.d/50-desktop.sh`, before the COPR block, with the comment `# The desktop installs user applications from Flathub; the server has no Flatpak`.

- [ ] **Step 6: Point the Node assertion at the desktop manifest**

In `tests/test-static.sh`, the check at line 262 reads `$manifest` (which is `packages-common.txt` at line 53). Change its two manifest greps to use the desktop manifest declared at the top of the file instead:

```bash
if ! grep -qx 'nodejs' "$repo_root/manifests/packages-desktop.txt" ||
   ! grep -qx 'nodejs-npm' "$repo_root/manifests/packages-desktop.txt"; then
```

Leave the four `verify-image.sh` greps in that block untouched.

- [ ] **Step 7: Run the static gate to verify it passes**

Run: `tests/test-static.sh`
Expected: `static checks passed`, including `ok   the base names tailscale and no desktop package, and the server names restic`.

- [ ] **Step 8: Update the docs and changelog**

Add to `CHANGELOG.md` under the unreleased heading: `- Split the package manifests into a server-safe base, a desktop set, and a server set; Tailscale is now in every image.` Update `docs/build.md` where it describes the manifest split: name the three manifests, say which hook installs `packages-desktop.txt`, and state that `packages-server.txt` is installed through `PACKAGE_MANIFEST_EXTRA`.

- [ ] **Step 9: Commit**

```bash
git add manifests/ build/common.sh modules/desktop/usr/libexec/ultus-atomic/build.d/50-desktop.sh tests/test-static.sh CHANGELOG.md docs/build.md
git commit -m "refactor: split the package manifests by role (#149)"
```

---

### Task 2: Copy one module per Containerfile and add the server image

**Files:**
- Modify: `Containerfile:20`
- Modify: `Containerfile.nvidia:12`
- Create: `Containerfile.server`
- Create: `modules/server/usr/lib/systemd/system/var-srv.mount`
- Modify: `tests/test-static.sh` (ctx-tree block at lines 111-122, base-pin loop at 29-52)
- Modify: `.github/workflows/repin-base.yml:114-120`
- Docs: `CHANGELOG.md`, `docs/build.md`

**Interfaces:**
- Consumes: `manifests/packages-server.txt` from Task 1.
- Produces: `Containerfile.server` with `PACKAGE_MANIFEST_EXTRA=packages-server.txt`, a `FROM` line carrying the same digest as the other two, and exactly one `COPY modules/server /modules/server` line. `modules/server/` exists and holds one unit.

- [ ] **Step 1: Write the failing static assertions**

Replace the ctx-tree block in `tests/test-static.sh` with a loop over every Containerfile:

```bash
# Each host copies one module tree by name, so a host cannot inherit another
# host's module. build/common.sh copies whatever /ctx/modules/* it finds, so a
# COPY that drifts silently ships the wrong role.
ctx_trees=$(grep -oE '^COPY (build|manifests|overlay) ' "$repo_root/Containerfile")
for cf in "$repo_root"/Containerfile*; do
  [[ -f $cf ]] || continue
  name=${cf##*/}
  trees=$(grep -oE '^COPY (build|manifests|overlay) ' "$cf")
  module_lines=$(grep -cE '^COPY modules/[a-z]+ /modules/[a-z]+$' "$cf" || true)
  if [[ $trees != "$ctx_trees" ]]; then
    echo "FAIL ${name} exposes different build-context trees than Containerfile" >&2
    failures=$((failures + 1))
  elif ((module_lines != 1)); then
    echo "FAIL ${name} does not copy exactly one module tree by name" >&2
    failures=$((failures + 1))
  fi
done
case "$(grep -oE '^COPY modules/[a-z]+ /modules/[a-z]+$' "$repo_root/Containerfile")" in
  'COPY modules/desktop /modules/desktop') ;;
  *) echo "FAIL Containerfile does not copy modules/desktop" >&2; failures=$((failures + 1)) ;;
esac
case "$(grep -oE '^COPY modules/[a-z]+ /modules/[a-z]+$' "$repo_root/Containerfile.server")" in
  'COPY modules/server /modules/server') ;;
  *) echo "FAIL Containerfile.server does not copy modules/server" >&2; failures=$((failures + 1)) ;;
esac
echo "ok   every Containerfile copies one module tree by name"
```

Add after the base-pin loop:

```bash
# The repin workflow rewrites Containerfile and Containerfile.nvidia. A third
# Containerfile left behind silently keeps an old base, which is the drift the
# single-base rule exists to prevent.
mapfile -t base_digests < <(grep -hoE '^FROM registry\.fedoraproject\.org/fedora-bootc:45@sha256:[0-9a-f]{64}$' "$repo_root"/Containerfile* | sort -u)
if ((${#base_digests[@]} != 1)); then
  echo "FAIL the Containerfiles do not share one base pin" >&2
  failures=$((failures + 1))
else
  echo "ok   every Containerfile carries the same base pin"
fi
```

- [ ] **Step 2: Run the static gate to verify it fails**

Run: `tests/test-static.sh`
Expected: FAIL with `Containerfile does not copy modules/desktop` or `does not copy exactly one module tree by name`.

- [ ] **Step 3: Switch the two existing Containerfiles to named module copies**

In `Containerfile` line 20, replace `COPY modules /modules` with `COPY modules/desktop /modules/desktop`. In `Containerfile.nvidia` line 12, do the same.

- [ ] **Step 4: Create `Containerfile.server`**

Copy `Containerfile.nvidia` and change three things: drop the `ENV PACKAGE_MANIFEST_EXTRA` value to `packages-server.txt`, replace the module COPY with `COPY modules/server /modules/server`, and update the header comment to say this image is the headless server. The `FROM` digest, the `RUN --mount` line, and the trailing `RUN bootc container lint` stay identical to the desktop file.

- [ ] **Step 5: Create the server module's first unit**

`modules/server/usr/lib/systemd/system/var-srv.mount`:

```ini
[Unit]
Description=Ultus data disk
After=local-fs-pre.target
Before=local-fs.target

[Mount]
What=/dev/disk/by-label/ultus-data
Where=/var/srv
Type=ext4
Options=defaults,noatime,nofail
TimeoutSec=30

[Install]
WantedBy=local-fs.target
```

Add a comment above `[Unit]` naming the reason for `/var/srv`: `/srv` is a symlink in the base image and systemd refuses to mount on a symlinked path.

- [ ] **Step 6: Extend the repin workflow**

In `.github/workflows/repin-base.yml`, add `$repo_root/Containerfile.server` to the `sed -E ... -i` list and to `git add`. Change the comment `# Rewrite both Containerfiles atomically` to `# Rewrite every Containerfile atomically`.

- [ ] **Step 7: Run the static gate to verify it passes**

Run: `tests/test-static.sh`
Expected: `static checks passed`, including `ok   every Containerfile copies one module tree by name` and `ok   every Containerfile carries the same base pin`.

- [ ] **Step 8: Build the server image**

Run: `podman build -f Containerfile.server -t localhost/ultus-atomic-server:dev .`
Expected: the build completes. Then `podman run --rm localhost/ultus-atomic-server:dev test -f /usr/lib/systemd/system/var-srv.mount` exits 0, and `podman run --rm localhost/ultus-atomic-server:dev systemctl is-enabled var-srv.mount` prints `enabled`. A unit left disabled by the build is a `[Install]` bug, not a test bug.

If the image build fails because the unit is not enabled, check that the module tree landed at `/modules/server` and not `/modules`: `podman run --rm localhost/ultus-atomic-server:dev ls /usr/lib/systemd/system/var-srv.mount`.

- [ ] **Step 9: Update the docs and changelog**

Add `- Add Containerfile.server and modules/server, and copy one module tree per Containerfile.` to `CHANGELOG.md`. In `docs/build.md`, add the server row to whatever table names the images, and replace the "the build copies every `modules/*` tree" sentence with the named-copy rule.

- [ ] **Step 10: Commit**

```bash
git add Containerfile Containerfile.nvidia Containerfile.server modules/server tests/test-static.sh .github/workflows/repin-base.yml CHANGELOG.md docs/build.md
git commit -m "feat: add the server image and one module copy per host (#149)"
```

---

### Task 3: Verify the server image and build it in CI

**Files:**
- Modify: `tests/verify-image.sh:5-18` (usage and flag parsing), `:267-283` (desktop-only probes), and add a server block
- Create: `manifests/packages-server.lock`
- Modify: `.github/workflows/ci.yml:44-51` (outputs), `:53-80` (filter), and add a `server` job
- Docs: `CHANGELOG.md`, `docs/testing.md`

**Interfaces:**
- Consumes: `Containerfile.server` and `modules/server/` from Task 2.
- Produces: `tests/verify-image.sh --server` exits 0 only for an image with no desktop package, `var-srv.mount` present and enabled, `tailscale` and `restic` installed, and no Flathub remote. `manifests/packages-server.lock` holds exactly the two RPM Fusion release entries.

- [ ] **Step 1: Write the failing server verification**

In `tests/verify-image.sh`, add `server=0` next to `headless=0` and a flag case:

```bash
--server) server=1; shift ;;
```

and extend the usage line to `[--no-package-lock] [--headless] [--server] [image]`. Then:

1. Change the desktop-only package block (the `mesa-vulkan-drivers.i686`, `node`, and `npm` probes) to run only when `((!headless && !server))`.
2. Add, after it:

```bash
# The server image carries the base plus packages-server.txt and one module.
# Anything from the desktop manifest in it means the split failed, not that the
# verifier is strict.
if ((server)); then
  desktop_list=$(grep -Ev '^[[:space:]]*(#.*)?$' "$repo_root/manifests/packages-desktop.txt")
  if present=$("$runtime" run --rm "$image" rpm -q $desktop_list 2>/dev/null); then
    echo "FAIL the server image installs desktop packages:"$'\n'"$present" >&2
    exit 1
  fi
  "$runtime" run --rm "$image" test -f /usr/lib/systemd/system/var-srv.mount \
    || { echo "FAIL var-srv.mount is missing" >&2; exit 1; }
  "$runtime" run --rm "$image" systemctl is-enabled var-srv.mount | grep -qx enabled \
    || { echo "FAIL var-srv.mount is not enabled" >&2; exit 1; }
  "$runtime" run --rm "$image" rpm -q tailscale restic >/dev/null \
    || { echo "FAIL the server image lacks tailscale or restic" >&2; exit 1; }
  if "$runtime" run --rm "$image" test -e /etc/flatpak/remotes.d/flathub.flatpakrepo; then
    echo "FAIL the server image seeds the Flathub remote" >&2
    exit 1
  fi
  echo "ok   the server image carries no desktop package and mounts its data disk"
fi
```

3. Make the lock path role-dependent: replace the hardcoded `lock=$repo_root/manifests/packages-common.lock` with

```bash
lock=$repo_root/manifests/packages-common.lock
((server)) && lock=$repo_root/manifests/packages-server.lock
```

- [ ] **Step 2: Run the verifier against the server image to watch it fail**

Run: `tests/verify-image.sh --server localhost/ultus-atomic-server:dev`
Expected: FAIL with `manifests/packages-server.lock: No such file` (or the `var-srv.mount` line if the unit is missing).

- [ ] **Step 3: Generate the server lock**

Run:

```bash
build/package-lock.sh localhost/ultus-atomic-server:dev > manifests/packages-server.lock.tmp
mv manifests/packages-server.lock.tmp manifests/packages-server.lock
```

Then edit the header's first line to `# manifests/packages-server.lock - regenerate with build/package-lock.sh <image>`. Expected content: the two-line header plus `rpmfusion-free-release-0:45-2.noarch  @commandline` and `rpmfusion-nonfree-release-0:45-2.noarch  @commandline`, tab-separated. Anything else is a role leak: stop and fix the manifest instead of writing the lock.

- [ ] **Step 4: Run the verifier to verify it passes**

Run: `tests/verify-image.sh --server localhost/ultus-atomic-server:dev`
Expected: `ok   the server image carries no desktop package and mounts its data disk` and `ok   package lock comparison ...` with no drift.

- [ ] **Step 5: Prove the desktop image is unchanged**

Build the desktop image from the branch head and compare against the last `main` build:

```bash
podman build -t localhost/ultus-atomic:split .
podman run --rm localhost/ultus-atomic:split rpm -qa | sort > .tmp-after.txt
```

Expected: `.tmp-after.txt` equals the pre-split set plus `tailscale`, and `manifests/packages-common.lock` is unchanged (`git diff --exit-code manifests/packages-common.lock`). Build the pre-split image once from `origin/main` into `localhost/ultus-atomic:before` and diff the two sorted lists to confirm. Record both checks in the commit message, then `rm .tmp-after.txt` before committing so the tree stays clean.

- [ ] **Step 6: Add the CI path filter and job**

In `.github/workflows/ci.yml`: add `server: ${{ steps.server.outputs.server }}` to the `changes` job outputs, and a `changes` step whose regex is

```bash
regex='^(Containerfile$|Containerfile\.server$|build/|overlay/|modules/|manifests/packages-(common|desktop|server)[.]txt$|tests/verify-image[.]sh$)'
```

Then add a `image-server` job modelled on `image-nvidia` (`ci.yml:271-310`): filter on `needs.changes.outputs.server`, build with `podman build --layers -f Containerfile.server -t localhost/ultus-atomic-server:ci .`, and run `tests/verify-image.sh --server localhost/ultus-atomic-server:ci`. Do not add publishing in this task.

- [ ] **Step 7: Lint the workflows and gates**

Run: `tests/lint.sh && tests/test-static.sh`
Expected: both pass. A YAML error in `ci.yml` surfaces here.

- [ ] **Step 8: Update the docs and changelog**

Add `- Verify the server image in CI with its own lock and path filter.` to `CHANGELOG.md`. In `docs/testing.md`, add a row to the gate table naming `tests/verify-image.sh --server` and what it asserts, and note that the server VM slice is a later part.

- [ ] **Step 9: Commit**

```bash
git add tests/verify-image.sh manifests/packages-server.lock .github/workflows/ci.yml CHANGELOG.md docs/testing.md
git commit -m "test: verify the server image and build it in CI (#149)"
```

---

## Later Parts

This plan is part 1 of the spec. The remaining parts, each its own plan from the same spec:

| Part | Spec sections | Ends with |
| --- | --- | --- |
| 2. Server behaviour | Server module, Rootless agents, Data disk, Secrets, Updates, First boot and recovery | A booted server running both workloads as `agents`, with secrets, backup, health, and the window |
| 3. Publishing and promotion | Publishing, Container images | Three published packages, one promotion per host, and a digest delivery path |
| 4. Hardware | Tests (VM rows), Migration preconditions, Rollout | The vertical slice on a booted server, the EliteDesk installed, `devbox-oc` archived |

Do not start part 2 until the server image builds and verifies in CI, because every later task assumes that gate.

## Self-Review

**Spec coverage, part 1:**
- "Publish three images": the third image exists and builds in CI; publishing is part 3.
- "No desktop, greeter, Steam, Xfce, Flatpak, or developer toolchain": Task 1 moves the groups, Task 3 asserts absence plus no Flathub remote.
- "Tailscale in every image": Task 1 adds it to the base, Task 3 asserts it in the server image; the desktop and NVIDIA assertions arrive with part 3's lock work, and the desktop comparison in Task 1 step 5 names it explicitly.
- "Leave the desktop installed set unchanged apart from Tailscale": Task 1 step 5 and the unchanged common lock.
- "One GHCR package per host": part 3.
- "Mount the data disk by label at `/var/srv`": Task 2's unit, Task 3's assertion.
- Everything else is deferred by the table above, with no task missing a named owner.

**Step scan:** every step names one command or one edit with a checkable result. No step says "handle edge cases" or "add validation". The only judgement left open is the exact wording of the two comment blocks, which does not change behaviour.

**Type consistency:** `--server` is the flag in `verify-image.sh`; `packages-server.lock` and `packages-server.txt` keep the same stem; `var-srv.mount` uses `Where=/var/srv` everywhere, and no step reintroduces `srv.mount`.

**Review Focus:** each of the five lines has a test in the task that owns it: overlap check (Task 1), desktop `rpm -qa` comparison (Task 1 step 5), `rpm -q tailscale` (Task 3), ctx-tree loop (Task 2), shared base digest (Task 2).

**Proportion:** the plan is shorter than the spec it implements, and the only code blocks are the assertions and the unit file, both of which the spec fixes exactly.
