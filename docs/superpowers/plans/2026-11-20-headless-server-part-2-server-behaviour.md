# Headless Server Image, Part 2: Server Behaviour

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the part 1 server image into a server: two rootless agent workloads under a dedicated `agents` user, secrets read from the data partition, a tailnet join with the surfaces published, a quiesced backup that restores, and an update that applies only inside a maintenance window.

**Architecture:** One module tree, `modules/server/`, owns every file the server role ships, and its build hook owns the user, the linger flag and the unit enablement. Workloads are explicit `podman run` units rather than quadlets, because the isolation gate parses what will actually run. Secrets live once, on the data disk; each workload gets a derived file in tmpfs under `/run/ultus`. The data disk is a precondition for every workload unit, so a missing disk stops the agents instead of letting them write to the OS disk.

**Tech Stack:** Fedora 45 `fedora-bootc` base pinned by digest, systemd 262 units, rootless Podman 6.1.3, `bootc` 1.17.1, `tailscale`, `restic`, bash gates in `tests/`, QEMU boot tests, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-20-headless-server-image-design.md` (revision 3), sections Server module, Rootless agents, Data disk, Secrets, Updates, First boot and recovery.

**Work item:** #152, part 2 of #149.

## Decisions this plan settles

The spec delegates these to the builder. Each row is decided here, with the evidence that decided it.

| Open item | Decision | Evidence |
| --- | --- | --- |
| `agents` uid, gid, subuid base | uid 1000, gid 1000, subuid and subgid `100000:65536` | `useradd -u 1000 -g agents` and `usermod --add-subuids 100000-165535` both succeed on the pinned base; `getent passwd agents` printed `agents:x:1000:1000:...:/var/lib/agents:/sbin/nologin` |
| `--userns=keep-id` write access | keep `--userns=keep-id`, run the container as uid 1000 | Container `id` under `-u 1000 --userns=keep-id` on a uid 1000 host printed `uid=1000 gid=1000`; the mapping is one-to-one with `agents` |
| OpenCode lifecycle command | `serve --service --hostname 0.0.0.0 --port 4096` | Both forms stay in the foreground on the pinned workload image; `--service` additionally registers the endpoint, and the run answered `401` on `/api/info` under `--read-only` plus the tmpfs set below |
| Read-only root filesystem | `--read-only` plus tmpfs on `/tmp`, `/run`, `/home/dev/.config`, `/home/dev/.cache` | Without a writable `$HOME` the container exits 1 with `EROFS: read-only file system, mkdir '/home/dev/.local'`; with the four tmpfs and the two `$HOME` bind mounts it runs and serves. `/home/dev/.local` needs no tmpfs because the share bind mount creates it |
| Workload digest location | Build-time default in the unit's `Environment=`, overridden by `EnvironmentFile=-/var/srv/ultus/workloads.env`, writable by root only | Operator decision, 2026-11-20: part 2 does not move `containers/opencode` or build the digest update service |
| OpenCode and Hermes defaults | `ghcr.io/ultus-net/devbox@sha256:8649976df3ebbd38f8b6b323b2a8522cb7de6021e969f836ed57c0cf4ab5e81a` and `docker.io/nousresearch/hermes-agent@sha256:41468459379a943cf0a25a55589e230d244bd9f95b83cff5eca789470c892fac` | The devbox image is the published OpenCode v2.1.4 build; upstream `ghcr.io/anomalyco/opencode:latest` is v1.19.6 and runs as root, so it is the wrong pin. The Hermes digest is today's `:latest` amd64 manifest |
| Restic repository and retention | Same bucket, new prefix. `RESTIC_REPOSITORY` and `RESTIC_PASSWORD_FILE` come from `/var/srv/ultus/backup.env`; retention is `--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune` on a weekly timer | Operator decision, 2026-11-20 |
| Server host name | `ultus-server`, passed to `tailscale up --hostname` | Operator decision, 2026-11-20 |
| NVIDIA publishing | Out of scope | Part 3 (#153) |

Two spec statements are corrected, and the plan follows the correction:

- The spec contradicts itself on the derived env path. Its Secrets section names `/var/srv/opencode/env` and `/var/srv/hermes/env` (`docs/superpowers/specs/2026-11-20-headless-server-image-design.md:319-320`), and its Server module section names `/run/ultus/opencode.env` and `/run/ultus/hermes.env` (`:246`). The plan follows `:246`, because `/run` is tmpfs: a derived secret is regenerated at every boot and never becomes a second copy on the disk the backup covers.
- The spec's Server module section lists a tmpfiles rule for the data-disk subtree. tmpfiles runs after `local-fs.target` and would create `/var/srv/{ultus,opencode,hermes,repos}` on the OS disk when the data disk is absent. A oneshot unit that refuses to run unless `/var/srv` is a mountpoint replaces it.

## Evidence already recorded

Run on 2026-11-20, so the builder does not repeat them.

| Check | Command | Result |
| --- | --- | --- |
| Base user creation | `useradd -u 1000 -g agents -M -d /var/lib/agents -s /sbin/nologin agents` | `agents:x:1000:1000:...:/var/lib/agents:/sbin/nologin` |
| Subordinate ranges | `usermod --add-subuids 100000-165535 --add-subgids 100000-165535 agents` | `/etc/subuid:agents:100000:65536`, `/etc/subgid:agents:100000:65536` |
| Linger file | `touch /var/lib/systemd/linger/agents` | `-rw-r--r-- 1 root root 0 ... agents`; the file is what `loginctl enable-linger` writes |
| keep-id mapping | `podman run -u 1000 --userns=keep-id ... id` | `uid=1000 gid=1000 groups=1000` |
| Name resolution | rootless custom network, `getent hosts ultus-spike-a` | `10.89.0.2 ultus-spike-a.dns.podman` |
| OpenCode foreground | `serve --hostname 0.0.0.0 --port 4096` | container stays running, `/api/info` answers `401` |
| OpenCode service form | `serve --service ...` | container stays running, `server listening on http://0.0.0.0:4097` |
| OpenCode read-only | `--read-only` without `$HOME` tmpfs | exits 1, `EROFS ... mkdir '/home/dev/.local'` |
| OpenCode read-only, fixed | plus tmpfs on `/tmp /run /home/dev/.local /home/dev/.config /home/dev/.cache` | running, `/api/info` answers `401` |
| Base tooling | `command -v curl jq python3` in the base | `/usr/sbin/curl`, `/usr/sbin/jq`, `/usr/sbin/python3` |
| bootc flags | `bootc upgrade --help` | `--download-only`, `--from-downloaded` |
| Network create | `podman network create --help` | `--ignore  Don't fail if network already exists` |

## Already in the tree

Part 1 shipped these. Each task below extends them; none is created from scratch.

| Path | State | What part 2 adds |
| --- | --- | --- |
| `modules/server/usr/lib/systemd/system/var-srv.mount` | Present, mounts `LABEL=ultus-data` | Nothing |
| `modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh` | Present, enables and asserts `var-srv.mount` | The user, the linger flag, and every new enablement, appended |
| `manifests/packages-server.txt`, `packages-common.txt`, `packages-desktop.txt`, the two lock files | Present | Nothing; no package is added |
| `tests/lint.sh` | Present; already lints `50-server.sh` (`:52`) | One entry per new script and test |
| `tests/verify-image.sh` | Present; `--server` block at `:298-331` checks the desktop-package split, `var-srv.mount`, `tailscale`/`restic`, and the Flathub seed | The user, linger, unit enablement, `systemd-analyze verify`, and the drop-in |
| `.github/workflows/ci.yml` | Present; `image-server` (`:334-362`) builds and verifies with `timeout-minutes: 120`; `image` (`:169-296`) adds SBOM, the disk build, `boot-smoke.sh`, and the trivy scan | The boot step inside `image-server`; there is no separate boot job to copy |
| `tests/vm/boot-smoke.sh`, `tests/vm/make-disk.sh` | Present; the boot script takes `[disk.qcow2] [boot.log]`, the disk script takes `[image] [output-dir]` and pins bootc-image-builder by digest | A `boot.log`-compatible server script, and `SERVER_DISK=1` |

## Global Constraints

- One base pin: every `Containerfile*` carries the identical `FROM ...@sha256:...` digest. This part adds no Containerfile.
- Fedora packages first. Part 2 adds no package; `restic`, `tailscale`, `curl` and `jq` are already installed.
- No secret, key, or credential enters the image, the build log, or the repository. The module ships no `secrets.env`, no `backup.env`, and no default password.
- No unit creates, formats, relabels, or guesses a block device. `var-srv.mount` mounts `LABEL=ultus-data`; nothing else touches storage hardware.
- Every workload carries `RequiresMountsFor=/var/srv`. A missing data disk stops the agents; it never falls back to the OS disk.
- Every published port binds `127.0.0.1` only. The tailnet is the only way in.
- Every write path ships off by default. The four timers are health, backup, retention, and the update window. The last three do nothing until the operator writes `/var/srv/ultus/backup.env` and a deployment is staged.
- No unit writes outside the data disk, `/run`, and `/var/lib/ultus`.
- The static gate stays the cheapest gate and runs before any image builds.
- Every script this part creates is added to `tests/lint.sh`'s `bash_scripts` array in the same commit that creates it. The full list, so no step can forget one: `modules/server/usr/libexec/ultus/ultus-data-prepare`, `ultus-env`, `ultus-health`, `ultus-backup`, `ultus-tailnet`, `ultus-update-window`, then `tests/test-server-isolation.sh`, `tests/test-server-env.sh`, `tests/vm/lib/qemu.sh`, `tests/vm/boot-smoke-server.sh`.
- `manifests/packages-common.lock` and `manifests/packages-server.lock` must stay unchanged in the tree, because this part installs no package. They are two different files and are not compared with each other.

## Review Focus

The failure modes the spec implies and no shipped unit covers yet. Each has a test in the task that owns the code.

1. A workload that can reach the host home, `~/.ssh`, a Podman socket, or `/dev`. The isolation test parses the shipped units and rejects each adversarial spelling; the VM proves the runtime side with canary reads.
2. A derived env file left world-readable, or written with the whole secrets file. The env test asserts mode 0600, owner `agents`, and that only the workload's own keys appear.
3. A missing data disk that lets a container write to the OS disk. The VM boots with no second disk and asserts both workloads are inactive.
4. A backup that runs against an unmounted `/var/srv`, storing an empty tree that looks like a successful backup. The unit carries `ConditionPathIsMountPoint=`, the script repeats the check, and the VM asserts a restore actually contains files.
5. An update window that applies outside the window, or stops the workloads and never restarts them after a failure. The drop-in replaces `--apply` with `--download-only`, and the window restarts the workloads on every failure path.
6. A port published on `0.0.0.0`, which is a second door on the wired LAN. The static test rejects any publish without `127.0.0.1`, and the VM enumerates the live listener list.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh` | Creates `agents`, writes the linger flag, enables every unit, asserts the wiring |
| `modules/server/usr/libexec/ultus/ultus-data-prepare` | Creates the data-disk subtree; refuses when `/var/srv` is not a mountpoint |
| `modules/server/usr/libexec/ultus/ultus-env` | Derives one workload env file from `secrets.env`, atomically, mode 0600 |
| `modules/server/usr/libexec/ultus/ultus-health` | Probes both loopback surfaces; restarts the unit that is up but not answering |
| `modules/server/usr/libexec/ultus/ultus-tailnet` | Joins the tailnet once, enables SSH, publishes the three surfaces, removes the key |
| `modules/server/usr/libexec/ultus/ultus-backup` | Quiesced restic backup; restores nothing, but refuses an unmounted disk |
| `modules/server/usr/libexec/ultus/ultus-update-window` | Drains the workloads, applies a staged deployment, reboots; restarts them on failure |
| `modules/server/usr/lib/systemd/system/var-srv.mount` | Data disk, present from part 1 |
| `modules/server/usr/lib/systemd/system/ultus-data-prepare.service` | Data-disk subtree precondition |
| `modules/server/usr/lib/systemd/system/opencode-env.service`, `hermes-env.service` | Oneshot env derivation |
| `modules/server/usr/lib/systemd/system/opencode.service`, `hermes.service` | Rootless workload units |
| `modules/server/usr/lib/systemd/system/ultus-network.service` | Creates the `ultus` Podman network once |
| `modules/server/usr/lib/systemd/system/ultus-tailnet.service` | Tailnet join and publish |
| `modules/server/usr/lib/systemd/system/ultus-health.service`, `.timer` | One-minute health loop |
| `modules/server/usr/lib/systemd/system/ultus-backup.service`, `.timer` | 02:30 quiesced backup |
| `modules/server/usr/lib/systemd/system/ultus-backup-forget.service`, `.timer` | Weekly retention |
| `modules/server/usr/lib/systemd/system/ultus-update-window.service`, `.timer` | 04:00 apply window |
| `modules/server/usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/download-only.conf` | Replaces `--apply` with `--download-only` |
| `tests/test-server-isolation.sh` | New static gate; parses units, rejects a widened fixture |
| `tests/test-server-env.sh` | New host gate; runs `ultus-env` against fixture secrets in a container |
| `tests/fixtures/server-units/widened.service` | The adversarial unit the isolation test must reject |
| `tests/fixtures/server-secrets.env`, `server-secrets-partial.env` | Env test inputs, placeholders only |
| `tests/verify-image.sh` | `--server` block extended with the user, linger, units and listener assertions |
| `tests/vm/lib/qemu.sh` | QEMU boot plumbing extracted from `boot-smoke.sh` |
| `tests/vm/boot-smoke-server.sh` | Server boot, isolation canaries, backup restore, reboot continuity |
| `tests/vm/make-disk.sh` | Gains `SERVER_DISK=1` for a wheel test account and a labelled data disk |
| `.github/workflows/ci.yml` | Server filter covers the new tests, fixtures and `tests/vm/`; the disk build and boot step inside `image-server` |
| `docs/server.md` | First boot, secrets, backup and restore, update window, recovery |
| `docs/testing.md`, `docs/ci.md`, `README.md`, `CHANGELOG.md` | Gate table, filter list, docs index, changelog |

---

### Task 1: Spike the boot-time mechanisms

Four properties cannot be proven from a container, because each needs a booted system with systemd as PID 1. Run them before writing any unit, because a failure changes the unit shape.

**Files:**
- Modify: `docs/superpowers/plans/2026-11-20-headless-server-part-2-server-behaviour.md` (this file: record the results in "Spike results")
- Test: a booted server image from part 1

- [ ] **Step 1: Build and install a server disk with a data disk**

```bash
podman build -f Containerfile.server -t localhost/ultus-atomic-server:dev .
podman save localhost/ultus-atomic-server:dev | sudo podman load
sudo SERVER_DISK=1 tests/vm/make-disk.sh localhost/ultus-atomic-server:dev
```

`SERVER_DISK=1` is written in Task 8 and does two things: it puts the test account in `wheel`, and it writes a second qcow2 named `data.qcow2` whose filesystem is ext4 and whose label is `ultus-data`. Until Task 8 exists, build that second disk by hand with the same two properties, and check them with `blkid output/qcow2/data.qcow2`, which must print `LABEL="ultus-data"` and `TYPE="ext4"`.

- [ ] **Step 2: Prove linger gives `agents` a runtime directory with no login**

Boot the disk with both drives. Log in as the test account, then:

```bash
groupadd -g 1000 agents 2>/dev/null || true
useradd -u 1000 -g agents -M -d /var/lib/agents -s /sbin/nologin agents 2>/dev/null || true
loginctl enable-linger agents
loginctl show-user agents -p Linger
ls -ld /run/user/1000
loginctl list-sessions --no-legend | grep -c agents || true
```

Expected: `Linger=yes`, `/run/user/1000` owned `agents`, and `0` sessions for `agents`. A linger flag with no session and a live runtime directory is the property the spec needs.

- [ ] **Step 3: Prove rootless Podman starts from a system unit**

```bash
sudo systemd-run --unit=spike-podman --uid=agents --setenv=HOME=/var/lib/agents \
  --setenv=XDG_RUNTIME_DIR=/run/user/1000 --wait --collect \
  podman info --format '{{.Host.CgroupVersion}} {{.Host.Security.Rootless}}'
```

Expected: `v2 true`. A `v1` or `false` answer stops the task: the plan is revised, and rootful Podman is not substituted, because the isolation decision forbids it.

Then reboot with `systemctl reboot` and run the same command again before logging in. Expected: the same `v2 true`. That second run is what proves the system units in Tasks 4 and 5 can reach `/run/user/1000` from boot with no login, which is the ordering their `After=user-runtime-dir@1000.service` line assumes.

- [ ] **Step 4: Prove `--userns=keep-id` writes land owned by `agents`**

```bash
sudo -u agents env HOME=/var/lib/agents XDG_RUNTIME_DIR=/run/user/1000 \
  podman run --rm --userns=keep-id -u 1000 \
  -v /var/srv/opencode/share:/state:z \
  ghcr.io/ultus-net/devbox@sha256:8649976df3ebbd38f8b6b323b2a8522cb7de6021e969f836ed57c0cf4ab5e81a \
  sh -c 'touch /state/probe && id'
stat -c '%u:%g %n' /var/srv/opencode/share/probe
```

Expected: the container prints `uid=1000 gid=1000`, and the host prints `1000:1000`. Create `/var/srv/opencode/share` with `install -d -o agents -g agents` first if Task 5 has not shipped.

- [ ] **Step 5: Prove a session survives a container restart**

```bash
sudo -u agents env HOME=/var/lib/agents XDG_RUNTIME_DIR=/run/user/1000 podman run -d --name oc-spike \
  --userns=keep-id -u 1000 -e HOME=/home/dev --read-only \
  --tmpfs /tmp --tmpfs /run --tmpfs /home/dev/.config --tmpfs /home/dev/.cache \
  -v /var/srv/opencode/share:/home/dev/.local/share/opencode:z \
  -v /var/srv/opencode/config:/home/dev/.config/opencode:z \
  -v /var/srv/opencode/state:/home/dev/.local/state/opencode:z \
  -p 127.0.0.1:4096:4096 \
  ghcr.io/ultus-net/devbox@sha256:8649976df3ebbd38f8b6b323b2a8522cb7de6021e969f836ed57c0cf4ab5e81a \
  serve --service --hostname 0.0.0.0 --port 4096
podman logs oc-spike | grep 'server password'
```

Take the printed password, then create a session through the API with basic auth (`opencode:<password>`), confirm it lists, `podman restart oc-spike`, and list sessions again.

Expected: the session id from before the restart is still listed. Record the command form that produced it. If the session is gone, stop and report: restart continuity is a spec acceptance criterion, and the fix belongs in the image or the mount layout, not in a weaker test.

- [ ] **Step 6: Record the results in this plan**

Add a `## Spike results` section after "Already in the tree" with one row per step: command, observed output, date, and the podman and systemd versions from the guest. Commit it with the message `docs: record the part 2 mechanism spikes (#152)`.

---

### Task 2: Create the `agents` user and the data-disk prepare unit

**Files:**
- Modify: `modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh`
- Create: `modules/server/usr/libexec/ultus/ultus-data-prepare`
- Create: `modules/server/usr/lib/systemd/system/ultus-data-prepare.service`
- Modify: `tests/test-static.sh` (new server block, after the existing `packages-server.txt` block at lines 78-99)
- Modify: `tests/lint.sh` (add the new script to `bash_scripts`)
- Docs: `CHANGELOG.md`, `docs/build.md`

**Interfaces:**
- Produces: user `agents` uid 1000 gid 1000, home `/var/lib/agents`, shell `/sbin/nologin`, ranges `100000:65536`, linger flag at `/var/lib/systemd/linger/agents`. `ultus-data-prepare.service` is enabled and creates `/var/srv/ultus` (0700 `root:root`), `/var/srv/{opencode,hermes,repos}` (0750 `agents:agents`), and the four workload state directories (0700 `agents:agents`).

- [ ] **Step 1: Write the failing static assertions**

Append to `tests/test-static.sh`:

```bash
# The server runs its agents as a dedicated rootless user. A missing linger flag
# means no runtime directory, so rootless Podman cannot start; a missing range
# means containers cannot map their own users. Both are silent at build time, so
# name them here.
server_hook=$repo_root/modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh
prepare_unit=$repo_root/modules/server/usr/lib/systemd/system/ultus-data-prepare.service
if ! grep -qF 'useradd -u 1000 -g agents' "$server_hook"; then
  echo "FAIL the server hook does not create the agents user with uid 1000" >&2
  failures=$((failures + 1))
elif ! grep -qF 'var/lib/systemd/linger/agents' "$server_hook"; then
  echo "FAIL the server hook does not write the linger flag, so rootless podman cannot start" >&2
  failures=$((failures + 1))
elif ! grep -qF 'usermod --add-subuids 100000-165535 --add-subgids 100000-165535 agents' "$server_hook"; then
  echo "FAIL the server hook does not give agents a subordinate range" >&2
  failures=$((failures + 1))
elif ! grep -qF 'ConditionPathIsMountPoint=/var/srv' "$prepare_unit"; then
  echo "FAIL ultus-data-prepare.service does not refuse an unmounted /var/srv" >&2
  failures=$((failures + 1))
else
  echo "ok   the server hook creates agents with a range and linger, and the prepare unit refuses an unmounted disk"
fi
```

- [ ] **Step 2: Run the static gate to verify it fails**

Run: `tests/test-static.sh`
Expected: FAIL with `the server hook does not create the agents user with uid 1000`.

- [ ] **Step 3: Extend the server hook**

Append to `modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh`, after the existing mount assertion:

```bash
# The workloads are rootless, so they run as a dedicated user. The uid is fixed
# because container uid 1000 maps to it under --userns=keep-id, and a moved uid
# would leave every state directory owned by nobody. The subordinate range is
# what lets Podman map container users at all.
groupadd -g 1000 agents
useradd -u 1000 -g agents -M -d /var/lib/agents -s /sbin/nologin \
  -c "ultus agent workloads" agents
usermod --add-subuids 100000-165535 --add-subgids 100000-165535 agents

# loginctl enable-linger writes this file. The build runs with no systemd as PID
# 1, so loginctl cannot reach a manager here; the file is the whole effect, and
# systemd reads it on the first boot.
install -d -m 0755 /var/lib/systemd/linger
touch /var/lib/systemd/linger/agents
chmod 0644 /var/lib/systemd/linger/agents

systemctl enable ultus-data-prepare.service
```

- [ ] **Step 4: Create the prepare unit and its script**

`modules/server/usr/lib/systemd/system/ultus-data-prepare.service`:

```ini
[Unit]
Description=Prepare the ultus data-disk subtree
Documentation=file:///usr/libexec/ultus/ultus-data-prepare
RequiresMountsFor=/var/srv
ConditionPathIsMountPoint=/var/srv
After=var-srv.mount
Before=opencode-env.service hermes-env.service ultus-network.service ultus-tailnet.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/ultus/ultus-data-prepare

[Install]
WantedBy=multi-user.target
```

`modules/server/usr/libexec/ultus/ultus-data-prepare`:

```bash
#!/bin/bash
# Create the subtree the workloads mount. A tmpfiles rule cannot do this: it
# would create the same directories on the OS disk when the data disk is absent,
# and a container would then write to the wrong filesystem.
set -ouex pipefail

fail() { echo "ultus-data-prepare: $1" >&2; exit 1; }

mountpoint -q /var/srv || fail "/var/srv is not a mountpoint; the data disk did not mount"

# The secrets live here, so root owns this tree and only root may list it.
install -d -m 0700 -o root -g root /var/srv/ultus
install -d -m 0750 -o agents -g agents /var/srv/opencode /var/srv/hermes /var/srv/repos
install -d -m 0700 -o agents -g agents \
  /var/srv/opencode/share /var/srv/opencode/config /var/srv/opencode/state \
  /var/srv/hermes/data
install -d -m 0700 -o agents -g agents /var/lib/agents
```

`chmod 0755 modules/server/usr/libexec/ultus/ultus-data-prepare` and add the path to the `bash_scripts` array in `tests/lint.sh`.

- [ ] **Step 5: Run the static gate to verify it passes**

Run: `tests/test-static.sh && CONTAINER_RUNTIME=podman tests/lint.sh`
Expected: `static checks passed`, then `apt mirror failover checks passed` and a clean shellcheck for the new script.

- [ ] **Step 6: Build the image and assert the wiring**

```bash
podman build -f Containerfile.server -t localhost/ultus-atomic-server:dev .
podman run --rm localhost/ultus-atomic-server:dev bash -lc '
  getent passwd agents && grep ^agents: /etc/subuid /etc/subgid &&
  test -f /var/lib/systemd/linger/agents && systemctl is-enabled ultus-data-prepare.service'
```

Expected: the passwd line, both range lines, and `enabled`.

- [ ] **Step 7: Update the docs and changelog**

Add to `CHANGELOG.md`: `- Create the server's rootless agents user and a unit that prepares the data-disk subtree only when the disk is mounted (#152).` In `docs/build.md`, name the new hook step and the user it creates.

- [ ] **Step 8: Commit**

```bash
git add modules/server tests/test-static.sh tests/lint.sh CHANGELOG.md docs/build.md
git commit -m "feat: create the server agents user and data-disk prep (#152)"
```

---

### Task 3: Derive workload secrets

**Files:**
- Create: `modules/server/usr/libexec/ultus/ultus-env`
- Create: `modules/server/usr/lib/systemd/system/opencode-env.service`
- Create: `modules/server/usr/lib/systemd/system/hermes-env.service`
- Create: `tests/test-server-env.sh`
- Create: `tests/fixtures/server-secrets.env`, `tests/fixtures/server-secrets-partial.env`
- Modify: `tests/test-static.sh` (assert both units name their workload)
- Modify: `tests/lint.sh` (add the script and the test)
- Docs: `CHANGELOG.md`, `docs/server.md` (first version of the page)

**Interfaces:**
- Produces: `/usr/libexec/ultus/ultus-env <opencode|hermes>` reads `/var/srv/ultus/secrets.env` and writes `/run/ultus/<workload>.env`, mode 0600, owner `agents`, containing only that workload's keys. Any missing required key exits 1 with a message naming the key.
- `opencode-env.service` and `hermes-env.service` are `Type=oneshot`, `RemainAfterExit=yes`, `RequiresMountsFor=/var/srv`, `After=ultus-data-prepare.service`.

- [ ] **Step 1: Write the failing test**

`tests/test-server-env.sh`:

```bash
#!/usr/bin/env bash
# Run ultus-env against fixture secrets and assert what it wrote, with no host
# service manager and no hidden dependency on the caller's environment.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runtime=${CONTAINER_RUNTIME:-podman}
image=${TEST_IMAGE:-registry.fedoraproject.org/fedora-bootc:45}
script=$repo_root/modules/server/usr/libexec/ultus/ultus-env
fixtures=$repo_root/tests/fixtures

# Run the script inside the image with /var/srv and /run bind-mapped, so the
# `mountpoint` check sees a real mount. A tmpfs on /var/srv is that mount.
run_case() {
  local secrets=$1 workload=$2
  "$runtime" run --rm \
    --mount "type=bind,src=${secrets},dst=/secrets.env,ro" \
    --mount "type=bind,src=${script},dst=/ultus-env,ro" \
    --tmpfs /var/srv --tmpfs /run \
    --entrypoint bash "$image" -c "
      # The base image has no agents user. Task 2 creates it at build time, and
      # the script chowns to it, so create the same pair here rather than pull a
      # built image into a gate that must run on a clean checkout.
      groupadd -g 1000 agents
      useradd -u 1000 -g agents -M -d /var/lib/agents -s /sbin/nologin agents
      install -d -m 0700 /var/srv/ultus
      cp /secrets.env /var/srv/ultus/secrets.env
      chmod 0600 /var/srv/ultus/secrets.env
      /ultus-env ${workload}
      stat -c '%a %U:%G' /run/ultus/${workload}.env
      sort /run/ultus/${workload}.env
    "
}

out=$(run_case "$fixtures/server-secrets.env" opencode)
grep -qx '600 agents:agents' <<<"$out" || { echo "FAIL the opencode env is not 0600 agents:agents: $out" >&2; exit 1; }
grep -qx 'OPENCODE_PASSWORD=server-secret' <<<"$out" || { echo "FAIL the opencode password is missing from the derived env" >&2; exit 1; }
if grep -q 'API_SERVER_KEY' <<<"$out"; then
  echo "FAIL the opencode env carries a key only Hermes needs" >&2; exit 1
fi
echo "ok   the opencode env holds its own keys, 0600, owned by agents"

out=$(run_case "$fixtures/server-secrets.env" hermes)
grep -qx 'API_SERVER_KEY=api-key' <<<"$out" || { echo "FAIL the Hermes env is missing its API key" >&2; exit 1; }
grep -qx 'OPENROUTER_API_KEY=provider-key' <<<"$out" || { echo "FAIL the Hermes env is missing the provider key" >&2; exit 1; }
echo "ok   the Hermes env holds the required keys and the provider key"

for case in opencode hermes; do
  rc=0
  out=$(run_case "$fixtures/server-secrets-partial.env" "$case" 2>&1) || rc=$?
  if [[ $rc -eq 0 ]]; then
    echo "FAIL ultus-env ${case} accepted a secrets file with no password" >&2
    exit 1
  fi
  echo "ok   ultus-env ${case} failed closed on a missing required key"
done

echo "server env tests passed"
```

`tests/fixtures/server-secrets.env`:

```text
# Fixture for tests/test-server-env.sh. Every value is a placeholder.
OPENCODE_PASSWORD=server-secret
API_SERVER_KEY=api-key
OPENROUTER_API_KEY=provider-key
TZ=UTC
```

`tests/fixtures/server-secrets-partial.env`:

```text
# Fixture for the fail-closed case: no OPENCODE_PASSWORD, no API_SERVER_KEY.
OPENROUTER_API_KEY=provider-key
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `CONTAINER_RUNTIME=podman tests/test-server-env.sh`
Expected: FAIL, because `modules/server/usr/libexec/ultus/ultus-env` does not exist.

- [ ] **Step 3: Write `ultus-env`**

```bash
#!/bin/bash
# Derive one workload's environment file from the operator's secrets file.
#
# The secrets file is data. This parses it rather than sourcing it, so a value
# cannot execute anything, and each workload sees only the keys it needs: a
# backup or a dashboard bug in one container cannot read the other's secrets.
set -ouex pipefail

workload=${1:-}
case $workload in
  opencode|hermes) ;;
  *) echo "ultus-env: usage: ultus-env opencode|hermes" >&2; exit 2 ;;
esac

secrets=/var/srv/ultus/secrets.env
out=/run/ultus/${workload}.env

fail() { echo "ultus-env: $1" >&2; exit 1; }

mountpoint -q /var/srv || fail "/var/srv is not a mountpoint; the data disk did not mount"
[[ -r $secrets ]] || fail "cannot read $secrets"

case $workload in
  opencode)
    required=(OPENCODE_PASSWORD)
    passthrough=(OPENCODE_PASSWORD TZ)
    ;;
  hermes)
    required=(OPENCODE_PASSWORD API_SERVER_KEY)
    provider=(OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY)
    passthrough=(OPENCODE_PASSWORD API_SERVER_KEY "${provider[@]}"
      HERMES_DASHBOARD_BASIC_AUTH_USERNAME HERMES_DASHBOARD_BASIC_AUTH_PASSWORD
      HERMES_DASHBOARD_BASIC_AUTH_SECRET TELEGRAM_BOT_TOKEN DISCORD_BOT_TOKEN TZ)
    ;;
esac

declare -A val=()
while IFS= read -r line || [[ -n $line ]]; do
  line=${line%$'\r'}
  [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
  [[ $line == *=* ]] || continue
  key=${line%%=*}
  value=${line#*=}
  case $value in
    \"*\") value=${value#\"}; value=${value%\"} ;;
    \'*\') value=${value#\'}; value=${value%\'} ;;
  esac
  val[$key]=$value
done <"$secrets"

for key in "${required[@]}"; do
  [[ -n ${val[$key]:-} ]] || fail "$key is unset or empty in $secrets"
done

if [[ $workload == hermes ]]; then
  found=0
  for key in "${provider[@]}"; do
    [[ -n ${val[$key]:-} ]] && found=1
  done
  ((found)) || fail "no model provider key is set in $secrets"
fi

install -d -m 0750 -o root -g agents /run/ultus
tmp=$(mktemp "/run/ultus/.${workload}.env.XXXXXX")
trap 'rm -f "$tmp"' EXIT
for key in "${passthrough[@]}"; do
  [[ -n ${val[$key]:-} ]] || continue
  printf '%s=%s\n' "$key" "${val[$key]}"
done >"$tmp"
chown agents:agents "$tmp"
chmod 0600 "$tmp"
# mv replaces the target atomically, so a workload never reads a half-written file.
mv -f "$tmp" "$out"
trap - EXIT

echo "ultus-env: wrote $out"
```

`chmod 0755` the script. Add it to `tests/lint.sh`'s `bash_scripts` and add `bash tests/test-server-env.sh` beside the other test invocations.

- [ ] **Step 4: Run the test to verify it passes**

Run: `CONTAINER_RUNTIME=podman tests/test-server-env.sh`
Expected: `server env tests passed`.

- [ ] **Step 5: Add the two env units**

`opencode-env.service`:

```ini
[Unit]
Description=Derive the OpenCode environment from the data-disk secrets
RequiresMountsFor=/var/srv
After=ultus-data-prepare.service var-srv.mount
Before=opencode.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/ultus/ultus-env opencode

[Install]
WantedBy=multi-user.target
```

`hermes-env.service` is identical with `Description=Derive the Hermes environment from the data-disk secrets`, `Before=hermes.service`, and `ExecStart=/usr/libexec/ultus/ultus-env hermes`.

- [ ] **Step 6: Enable both units in the hook and assert them**

Append to `modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh`:

```bash
systemctl enable opencode-env.service hermes-env.service
for unit in opencode-env.service hermes-env.service; do
  enabled=$(systemctl is-enabled "$unit" || true)
  [[ $enabled == enabled ]] || {
    echo "$unit is not enabled (got: ${enabled:-nothing}); the workload would start with no secrets" >&2
    exit 1
  }
done
```

Add a static assertion that each env unit runs its own workload:

```bash
for pair in 'opencode-env.service:opencode' 'hermes-env.service:hermes'; do
  unit=${pair%%:*}
  role=${pair##*:}
  if ! grep -qF "/usr/libexec/ultus/ultus-env ${role}" \
      "$repo_root/modules/server/usr/lib/systemd/system/${unit}"; then
    echo "FAIL ${unit} does not derive the ${role} environment" >&2
    failures=$((failures + 1))
  fi
done
```

- [ ] **Step 7: Run the gates**

Run: `tests/test-static.sh && CONTAINER_RUNTIME=podman tests/lint.sh && CONTAINER_RUNTIME=podman tests/test-server-env.sh`
Expected: all three pass.

- [ ] **Step 8: Write the first `docs/server.md`**

Sections: what the server image is; first boot (the `systemd.debug_shell` route from `docs/install.md:67`, then `/var/srv` check, `/var/srv/ultus` creation, `secrets.env` and `backup.env` contents with every key named, the tailnet key); how to confirm each workload is up; and the recovery route (`bootc rollback --apply`). Link it from `README.md` after the Install entry and add a row to `docs/testing.md`'s gate table for `tests/test-server-env.sh`.

- [ ] **Step 9: Commit**

```bash
git add modules/server tests/fixtures tests/test-server-env.sh tests/test-static.sh tests/lint.sh docs/server.md docs/testing.md README.md CHANGELOG.md
git commit -m "feat: derive workload secrets on the server (#152)"
```

---

### Task 4: Run the workloads rootless

**Files:**
- Create: `modules/server/usr/lib/systemd/system/opencode.service`
- Create: `modules/server/usr/lib/systemd/system/hermes.service`
- Create: `modules/server/usr/lib/systemd/system/ultus-network.service`
- Create: `tests/test-server-isolation.sh`
- Create: `tests/fixtures/server-units/widened.service`
- Modify: `modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh` (enable the three units)
- Modify: `tests/lint.sh` (add the test)
- Docs: `CHANGELOG.md`, `docs/server.md`, `docs/testing.md`

**Interfaces:**
- Produces: `opencode.service` and `hermes.service` as `User=agents` units running explicit `podman run` commands with `--userns=keep-id`, `--read-only`, `--cap-drop=all`, `--security-opt no-new-privileges`, one `-p 127.0.0.1:` per port, and image references from `EnvironmentFile=-/var/srv/ultus/workloads.env` over build-time defaults.
- `tests/test-server-isolation.sh` exits 0 on the shipped units and 1 on `tests/fixtures/server-units/widened.service`.

- [ ] **Step 1: Write the failing isolation test**

`tests/fixtures/server-units/widened.service` is a real unit that carries every rejected spelling:

```ini
[Unit]
Description=Adversarial fixture: every isolation failure in one unit

[Service]
User=root
ExecStart=/usr/bin/podman run --privileged --network=host --pid=host --ipc=host \
  --userns=host --cap-add=NET_ADMIN --security-opt label=disable \
  -v /home:/host -v /root/.ssh:/ssh \
  --mount=type=bind,source=/run/podman/podman.sock,destination=/var/run/docker.sock \
  --device /dev/kvm -p 4096:4096 \
  localhost/example:latest
```

`tests/test-server-isolation.sh`:

```bash
#!/usr/bin/env bash
# The server's isolation contract, asserted by parsing the units that will run.
# A static check is cheap enough to run on every push; the VM test proves the
# runtime side with canary reads.
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
units=$repo_root/modules/server/usr/lib/systemd/system
fixture=$repo_root/tests/fixtures/server-units

required=(
  'User=agents'
  '--userns=keep-id'
  '--cap-drop=all'
  '--security-opt no-new-privileges'
  '--read-only'
  'RequiresMountsFor=/var/srv'
)
forbidden=(
  '--privileged'
  '--network=host'
  '--network host'
  '--pid=host'
  '--ipc=host'
  '--userns=host'
  '--cap-add'
  'label=disable'
  '--device'
  # A host-home or root-home mount is the escape. The workloads do mount paths
  # under /home/dev inside the container, so the token has to name the host
  # side: '/home:' matches '-v /home:/host' and not '-v /var/srv/x:/home/dev/x'.
  '/home:'
  '/root'
  '.ssh'
  'podman.sock'
  'docker.sock'
)

failures=0
check_dir() {
  local dir=$1 strict=$2 unit text token publish
  for unit in "$dir"/*.service; do
    [[ -f $unit ]] || continue
    text=$(cat "$unit")
    for token in "${forbidden[@]}"; do
      if [[ $text == *"$token"* ]]; then
        echo "FAIL ${unit##*/} carries the rejected token '$token'" >&2
        failures=$((failures + 1))
      fi
    done
    # A publish without a loopback address binds every interface. This runs for
    # every unit, including the fixture, so the fixture proves the check fires.
    while IFS= read -r publish; do
      [[ -z $publish ]] && continue
      if [[ $publish != *'127.0.0.1:'* ]]; then
        echo "FAIL ${unit##*/} publishes outside loopback: $publish" >&2
        failures=$((failures + 1))
      fi
    done < <(grep -oE '(-p|--publish)[= ][^ ]+' "$unit" | sed -E 's/^(-p|--publish)[= ]//')
    [[ $strict == 1 ]] || continue
    case ${unit##*/} in
      opencode.service|hermes.service) ;;
      *) continue ;;
    esac
    for token in "${required[@]}"; do
      if [[ $text != *"$token"* ]]; then
        echo "FAIL ${unit##*/} is missing '$token'" >&2
        failures=$((failures + 1))
      fi
    done
  done
}

# The parser must reject the fixture first, or a green run on the real units
# proves nothing.
check_dir "$fixture" 0
if ((failures == 0)); then
  echo "FAIL the isolation parser accepted the widened fixture" >&2
  exit 1
fi
echo "ok   the parser rejects the widened fixture ($failures findings)"

failures=0
check_dir "$units" 1
((failures == 0)) || exit 1
echo "ok   every server unit is loopback-only and neither workload can reach the host"

# A workload that publishes nothing is not a server, and a missing port means the
# tailnet serves nothing.
for pair in 'opencode.service:4096' 'hermes.service:8642:9119'; do
  unit=${pair%%:*}
  ports=${pair#*:}
  for port in ${ports//:/ }; do
    grep -q -- "-p 127.0.0.1:${port}:${port}" "$units/$unit" || {
      echo "FAIL ${unit} does not publish 127.0.0.1:${port}" >&2
      exit 1
    }
  done
done
echo "ok   each workload publishes its own loopback ports"
echo "server isolation checks passed"
```

The fixture pass runs the forbidden list and the publish list only, because a fixture that also had to carry every required token would be a real unit. The strict pass covers the shipped workloads. The fixture's `-p 4096:4096` is what proves the publish check fires at all.

- [ ] **Step 2: Run the test to verify it fails**

Run: `tests/test-server-isolation.sh`
Expected: FAIL, because `modules/server/usr/lib/systemd/system/opencode.service` does not exist.

- [ ] **Step 3: Write `opencode.service`**

```ini
[Unit]
Description=OpenCode agent server (rootless)
Documentation=https://opencode.ai/docs/server/
Wants=network-online.target
Requires=opencode-env.service ultus-network.service
RequiresMountsFor=/var/srv
After=opencode-env.service ultus-network.service user-runtime-dir@1000.service network-online.target
Before=ultus-health.service

[Service]
Type=simple
User=agents
Environment=HOME=/var/lib/agents
Environment=XDG_RUNTIME_DIR=/run/user/1000
# The image reference is a build-time default. The override file is the one
# place a digest moves, and only root on the host can write it.
Environment=OPENCODE_IMAGE=ghcr.io/ultus-net/devbox@sha256:8649976df3ebbd38f8b6b323b2a8522cb7de6021e969f836ed57c0cf4ab5e81a
EnvironmentFile=/run/ultus/opencode.env
EnvironmentFile=-/var/srv/ultus/workloads.env
ExecStart=/usr/bin/podman run --rm --name opencode \
  --userns=keep-id -u 1000 -e HOME=/home/dev \
  --read-only \
  --tmpfs /tmp --tmpfs /run \
  --tmpfs /home/dev/.config --tmpfs /home/dev/.cache \
  --cap-drop=all --security-opt no-new-privileges \
  --network ultus \
  -p 127.0.0.1:4096:4096 \
  -v /var/srv/repos:/home/dev/repos:z \
  -v /var/srv/opencode/share:/home/dev/.local/share/opencode:z \
  -v /var/srv/opencode/config:/home/dev/.config/opencode:z \
  -v /var/srv/opencode/state:/home/dev/.local/state/opencode:z \
  ${OPENCODE_IMAGE} \
  serve --service --hostname 0.0.0.0 --port 4096
Restart=on-failure
RestartSec=10
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
```

The `--tmpfs /home/dev/.local` from the spike is deliberately absent: `/var/srv/opencode/share` is mounted at `/home/dev/.local/share/opencode`, so `/home/dev/.local` must already exist in the image. It does: the devbox image creates the user with `-m` and the quadlet has always mounted under it. If the first boot logs `mkdir '/home/dev/.local'`, add `--tmpfs /home/dev/.local` before the bind mount, which podman applies in order.

- [ ] **Step 4: Write `hermes.service`**

```ini
[Unit]
Description=Hermes agent control plane (rootless)
Wants=network-online.target
Requires=hermes-env.service ultus-network.service
RequiresMountsFor=/var/srv
After=hermes-env.service opencode.service ultus-network.service user-runtime-dir@1000.service network-online.target
Before=ultus-health.service

[Service]
Type=simple
User=agents
Environment=HOME=/var/lib/agents
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=HERMES_IMAGE=docker.io/nousresearch/hermes-agent@sha256:41468459379a943cf0a25a55589e230d244bd9f95b83cff5eca789470c892fac
Environment=HERMES_DASHBOARD=1
Environment=API_SERVER_ENABLED=true
Environment=API_SERVER_HOST=0.0.0.0
Environment=PUID=1000
Environment=PGID=1000
EnvironmentFile=/run/ultus/hermes.env
EnvironmentFile=-/var/srv/ultus/workloads.env
ExecStart=/usr/bin/podman run --rm --name hermes \
  --userns=keep-id -u 1000 \
  --read-only \
  --tmpfs /tmp --tmpfs /run \
  --cap-drop=all --security-opt no-new-privileges \
  --network ultus \
  -p 127.0.0.1:8642:8642 \
  -p 127.0.0.1:9119:9119 \
  -v /var/srv/hermes/data:/opt/data:z \
  ${HERMES_IMAGE} gateway run
Restart=on-failure
RestartSec=10
TimeoutStartSec=180

[Install]
WantedBy=multi-user.target
```

The image runs under s6 as root and drops to `PUID`/`PGID`; `-u 1000` plus `keep-id` keeps that pair equal to `agents`. If the first boot exits with a write to a path under `/var` or `/etc`, add the smallest tmpfs that covers it and record the addition in the unit's comment, not in a wider mount.

- [ ] **Step 5: Write `ultus-network.service`**

```ini
[Unit]
Description=Create the ultus Podman network
RequiresMountsFor=/var/srv
After=ultus-data-prepare.service user-runtime-dir@1000.service
Wants=user-runtime-dir@1000.service

[Service]
Type=oneshot
RemainAfterExit=yes
User=agents
Environment=HOME=/var/lib/agents
Environment=XDG_RUNTIME_DIR=/run/user/1000
ExecStart=/usr/bin/podman network create --ignore ultus

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 6: Enable the units and run the gates**

Append to the server hook:

```bash
systemctl enable ultus-network.service opencode.service hermes.service
for unit in ultus-network.service opencode.service hermes.service; do
  enabled=$(systemctl is-enabled "$unit" || true)
  [[ $enabled == enabled ]] || {
    echo "$unit is not enabled (got: ${enabled:-nothing})" >&2
    exit 1
  }
done
```

Run: `tests/test-server-isolation.sh && tests/test-static.sh && CONTAINER_RUNTIME=podman tests/lint.sh`
Expected: `server isolation checks passed`, then `static checks passed`, then a clean lint.

- [ ] **Step 7: Build and inspect**

```bash
podman build -f Containerfile.server -t localhost/ultus-atomic-server:dev .
podman run --rm localhost/ultus-atomic-server:dev bash -lc \
  'for u in ultus-network opencode hermes opencode-env hermes-env; do printf "%s " "$u"; systemctl is-enabled "$u.service"; done'
```

Expected: `enabled` for all five.

- [ ] **Step 8: Update the docs and changelog**

`docs/server.md` gains the workload section: which subtree each workload sees, the two image defaults, where the override file is and who may write it, and the rule that a new mount needs an isolation-test change. `docs/testing.md` gains a row for `tests/test-server-isolation.sh`. `CHANGELOG.md` gains one line naming the rootless workload units.

- [ ] **Step 9: Commit**

```bash
git add modules/server tests/test-server-isolation.sh tests/fixtures/server-units tests/lint.sh docs/server.md docs/testing.md CHANGELOG.md
git commit -m "feat: run the server workloads rootless with an isolation gate (#152)"
```

---

### Task 5: Join the tailnet and publish the surfaces

**Files:**
- Create: `modules/server/usr/libexec/ultus/ultus-tailnet`
- Create: `modules/server/usr/lib/systemd/system/ultus-tailnet.service`
- Modify: `modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh` (enable it)
- Modify: `tests/test-static.sh` (assert the three serve calls and the host name)
- Modify: `tests/lint.sh`
- Docs: `CHANGELOG.md`, `docs/server.md`

**Interfaces:**
- Produces: `ultus-tailnet.service` joins with `--hostname=ultus-server`, runs `tailscale set --ssh=true`, publishes 443 to OpenCode, 8443 to the Hermes dashboard and 10000 to the Hermes gateway, and removes the auth key afterwards. An already-joined node skips the join.

- [ ] **Step 1: Write the failing static assertion**

```bash
tailnet_unit=$repo_root/modules/server/usr/lib/systemd/system/ultus-tailnet.service
tailnet_script=$repo_root/modules/server/usr/libexec/ultus/ultus-tailnet
for surface in '--https=443 http://127.0.0.1:4096' \
               '--https=8443 http://127.0.0.1:9119' \
               '--https=10000 http://127.0.0.1:8642'; do
  if ! grep -qF "$surface" "$tailnet_script"; then
    echo "FAIL the tailnet script does not publish '$surface'" >&2
    failures=$((failures + 1))
  fi
done
if ! grep -qx 'hostname=ultus-server' "$tailnet_script"; then
  echo "FAIL the tailnet script does not join as ultus-server" >&2
  failures=$((failures + 1))
elif ! grep -qF -- '--hostname="$hostname"' "$tailnet_script"; then
  echo "FAIL the tailnet join does not pass the host name" >&2
  failures=$((failures + 1))
elif ! grep -qF 'RequiresMountsFor=/var/srv' "$tailnet_unit"; then
  echo "FAIL ultus-tailnet.service can run before the data disk is mounted" >&2
  failures=$((failures + 1))
else
  echo "ok   the tailnet script publishes three loopback surfaces as ultus-server"
fi
```

- [ ] **Step 2: Run the static gate to verify it fails**

Run: `tests/test-static.sh`
Expected: FAIL with `the tailnet script does not publish '--https=443 ...'`.

- [ ] **Step 3: Write the script and the unit**

`modules/server/usr/libexec/ultus/ultus-tailnet`:

```bash
#!/bin/bash
# Join the tailnet once, then publish every surface over TLS.
#
# Loopback publication alone exposes nothing off the box, and this is the only
# path in: sshd stays disabled and no container port binds a wired interface.
set -ouex pipefail

key=/var/srv/ultus/tailscale-authkey
hostname=ultus-server

fail() { echo "ultus-tailnet: $1" >&2; exit 1; }

mountpoint -q /var/srv || fail "/var/srv is not a mountpoint; the data disk did not mount"

state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState // empty' || true)
if [[ $state != Running ]]; then
  [[ -r $key ]] || fail "no tailnet identity and no auth key at $key"
  tailscale up --auth-key="file:$key" --hostname="$hostname" --ssh=false
  # The key is single-use. Remove it whether or not the join reported success,
  # because a key left on disk is a second door with no owner.
  shred -u "$key" 2>/dev/null || rm -f "$key"
fi

# Tailscale SSH authenticates by tailnet identity, so this box carries no
# authorized_keys and no sshd.
tailscale set --ssh=true

# --bg keeps each mount across reboots. One target per invocation.
tailscale serve --bg --https=443 http://127.0.0.1:4096
tailscale serve --bg --https=8443 http://127.0.0.1:9119
tailscale serve --bg --https=10000 http://127.0.0.1:8642

tailscale serve status
```

`ultus-tailnet.service`:

```ini
[Unit]
Description=Join the tailnet and publish the loopback surfaces
RequiresMountsFor=/var/srv
Wants=network-online.target
After=var-srv.mount tailscaled.service network-online.target
Before=ultus-health.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/libexec/ultus/ultus-tailnet
# No Restart=: systemd refuses it on Type=oneshot, and `systemd-analyze verify`
# in Task 7 is what catches anyone who adds it back. A failed join leaves the
# workloads running locally; `systemctl restart ultus-tailnet` retries once the
# key is replaced.
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

`chmod 0755` the script, add it to `tests/lint.sh`, and enable the unit in the hook with the same `is-enabled` assertion the earlier tasks use.

- [ ] **Step 4: Run the gates**

Run: `tests/test-static.sh && tests/test-server-isolation.sh && CONTAINER_RUNTIME=podman tests/lint.sh`
Expected: all pass.

- [ ] **Step 5: Record the surfaces in `docs/server.md`**

Add the three URLs (`https://ultus-server.<tailnet>.ts.net`, `:8443`, `:10000`), what each one serves, and the rule that a new surface is a publish on `127.0.0.1` plus a `tailscale serve --bg` line plus an isolation-test run.

- [ ] **Step 6: Commit**

```bash
git add modules/server tests/test-static.sh tests/lint.sh docs/server.md CHANGELOG.md
git commit -m "feat: join the tailnet and publish the server surfaces (#152)"
```

---

### Task 6: Health, backup and the update window

**Files:**
- Create: `modules/server/usr/libexec/ultus/ultus-health`
- Create: `modules/server/usr/libexec/ultus/ultus-backup`
- Create: `modules/server/usr/libexec/ultus/ultus-update-window`
- Create: eight units, four timers, and `bootc-fetch-apply-updates.service.d/download-only.conf`
- Modify: `modules/server/usr/libexec/ultus-atomic/build.d/50-server.sh` (enable every unit and timer)
- Modify: `tests/test-static.sh` (assert the drop-in, the window order and the backup condition)
- Modify: `tests/lint.sh`
- Docs: `CHANGELOG.md`, `docs/server.md`

**Interfaces:**
- `ultus-health.timer` fires every minute and restarts a unit that is active but not answering.
- `ultus-backup.timer` fires at 02:30, stops both workloads, runs restic, and starts them again from `ExecStopPost`. It refuses an unmounted `/var/srv`.
- `ultus-backup-forget.timer` fires weekly and applies the 7/4/6 retention with `--prune`. The retired `devbox-oc` kept retention manual because a wrong forget is irreversible. The operator chose automatic retention on 2026-11-20, so the plan changes that posture deliberately: `--keep-*` bounds what the timer can delete, and `--prune` runs only after the keep policy has been applied.
- `ultus-update-window.timer` fires at 04:00, drains the workloads, applies a staged deployment, and reboots. A failure restarts the workloads and does not reboot.
- The drop-in replaces the stock `ExecStart` with `bootc upgrade --download-only --quiet`.

- [ ] **Step 1: Write the failing assertions**

```bash
backup_unit=$repo_root/modules/server/usr/lib/systemd/system/ultus-backup.service
backup_script=$repo_root/modules/server/usr/libexec/ultus/ultus-backup
window_script=$repo_root/modules/server/usr/libexec/ultus/ultus-update-window
dropin=$repo_root/modules/server/usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/download-only.conf
if ! grep -qF 'ConditionPathIsMountPoint=/var/srv' "$backup_unit"; then
  echo "FAIL ultus-backup.service would back up an unmounted /var/srv" >&2
  failures=$((failures + 1))
elif grep -qF 'EnvironmentFile=/var/srv/ultus/backup.env' "$backup_unit" \
    "$repo_root/modules/server/usr/lib/systemd/system/ultus-backup-forget.service"; then
  echo "FAIL a backup unit puts the repository credentials in systemd's unit environment" >&2
  failures=$((failures + 1))
elif ! grep -qF -- '--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune' "$backup_script"; then
  echo "FAIL ultus-backup does not apply the operator's retention policy" >&2
  failures=$((failures + 1))
elif ! grep -qE '^ExecStopPost=-?/usr/bin/systemctl start opencode\.service hermes\.service$' "$backup_unit"; then
  echo "FAIL ultus-backup.service does not restart the workloads after a failed or finished backup" >&2
  failures=$((failures + 1))
elif ! grep -qF 'bootc upgrade --download-only --quiet' "$dropin" ||
     ! grep -qE '^ExecStart=$' "$dropin"; then
  echo "FAIL the drop-in does not replace the stock update command with --download-only" >&2
  failures=$((failures + 1))
elif ! grep -qF 'bootc upgrade --from-downloaded --apply' "$window_script"; then
  echo "FAIL the window does not apply the staged deployment" >&2
  failures=$((failures + 1))
elif ! grep -qF 'systemctl start opencode.service hermes.service' "$window_script"; then
  echo "FAIL the window does not restart the workloads when the apply fails" >&2
  failures=$((failures + 1))
else
  echo "ok   the backup refuses an unmounted disk, restarts the workloads, and the window applies only a staged deployment"
fi
```

- [ ] **Step 2: Run the static gate to verify it fails**

Run: `tests/test-static.sh`
Expected: FAIL with `ultus-backup.service would back up an unmounted /var/srv`.

- [ ] **Step 3: Write the health script and units**

`ultus-health`:

```bash
#!/bin/bash
# Probe each workload's real endpoint and restart a unit that is up but not
# answering. A process check alone passes a server that serves nothing.
set -ouex pipefail

probe() {
  local unit=$1 url=$2 code
  systemctl is-active --quiet "$unit" || return 0
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)
  case $code in
    200|401) return 0 ;;
  esac
  echo "ultus-health: $url answered ${code:-nothing}; restarting $unit" >&2
  systemctl restart "$unit"
}

# 401 is healthy for both surfaces: the server is up and asking for credentials.
probe opencode.service http://127.0.0.1:4096/api/info
probe hermes.service http://127.0.0.1:8642/health
```

`ultus-health.service`:

```ini
[Unit]
Description=Probe the agent workloads and restart a silent one
After=opencode.service hermes.service

[Service]
Type=oneshot
ExecStart=/usr/libexec/ultus/ultus-health
```

`ultus-health.timer`:

```ini
[Unit]
Description=Probe the agent workloads every minute

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min
AccuracySec=10s

[Install]
WantedBy=timers.target
```

- [ ] **Step 4: Write the backup script and units**

`ultus-backup`:

```bash
#!/bin/bash
# Back up the data disk, or apply the retention policy, with the workloads
# stopped for the backup.
#
# /var/srv is a plain directory on the OS disk when the mount fails, and backing
# that up stores an empty tree that looks like a backup. Refuse it here as well as
# in the unit, because a manual run bypasses the unit.
#
#   ultus-backup          back up
#   ultus-backup forget   apply the retention policy
set -ouex pipefail

op=${1:-backup}
case $op in
  backup|forget) ;;
  *) echo "ultus-backup: usage: ultus-backup [backup|forget]" >&2; exit 2 ;;
esac

fail() { echo "ultus-backup: $1" >&2; exit 1; }

env_file=/var/srv/ultus/backup.env

mountpoint -q /var/srv || fail "/var/srv is not a mountpoint; the data disk did not mount"
[[ -r $env_file ]] || fail "cannot read $env_file"

# Read the credentials here rather than through EnvironmentFile=: systemd
# publishes a unit's environment to unprivileged `systemctl show`, and this file
# holds the repository credentials. Only the RESTIC_*, AWS_* and B2_* keys are
# exported, so the workloads' secrets cannot reach the restic process.
file_mode=$(stat -c '%a %U' "$env_file")
[[ $file_mode == '600 root' ]] || fail "$env_file must be mode 0600 owned by root, got $file_mode"

while IFS= read -r line || [[ -n $line ]]; do
  [[ $line =~ ^[[:space:]]*(#|$) ]] && continue
  key=${line%%=*}
  case $key in
    RESTIC_*|AWS_*|B2_*) export "$key=${line#*=}" ;;
  esac
done <"$env_file"

: "${RESTIC_REPOSITORY:?$env_file must set RESTIC_REPOSITORY}"
export RESTIC_PASSWORD_FILE=${RESTIC_PASSWORD_FILE:-/var/srv/ultus/restic-password}

# The secret files are inside the backup on purpose: the repository is the only
# way to rebuild after a disk failure.
if [[ $op == forget ]]; then
  exec restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
fi
exec restic backup \
  --tag ultus-server \
  --exclude-caches \
  /var/srv/ultus /var/srv/opencode /var/srv/hermes /var/srv/repos
```

`ultus-backup.service`:

```ini
[Unit]
Description=Quiesced backup of the ultus data disk
RequiresMountsFor=/var/srv
ConditionPathIsMountPoint=/var/srv
After=var-srv.mount

[Service]
Type=oneshot
# No EnvironmentFile=: the credentials would become readable through
# `systemctl show`. ultus-backup reads the same file itself, mode 0600 root.
# The workloads must not be writing while restic reads. ExecStopPost starts them
# again on every exit path, so a failed backup never leaves the box down.
ExecStartPre=/usr/bin/systemctl stop opencode.service hermes.service
ExecStart=/usr/libexec/ultus/ultus-backup
ExecStopPost=-/usr/bin/systemctl start opencode.service hermes.service
TimeoutStartSec=3600
```

No `[Install]` section: the timer is the only thing that starts a backup, and a
service listed under `timers.target` would try to start at boot.

`ultus-backup.timer`:

```ini
[Unit]
Description=Back up the ultus data disk nightly

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
```

`ultus-backup-forget.service`:

```ini
[Unit]
Description=Apply the restic retention policy
# The same script reads the credentials, so this unit carries no EnvironmentFile=
# and nothing reaches `systemctl show`.
RequiresMountsFor=/var/srv
After=ultus-backup.service

[Service]
Type=oneshot
ExecStart=/usr/libexec/ultus/ultus-backup forget
TimeoutStartSec=3600
```

`ultus-backup-forget.timer`:

```ini
[Unit]
Description=Apply the restic retention policy weekly

[Timer]
OnCalendar=Sun *-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

- [ ] **Step 5: Write the update drop-in and the window**

`bootc-fetch-apply-updates.service.d/download-only.conf`:

```ini
# The stock unit runs `bootc upgrade --apply --quiet`, and --apply reboots into
# the new deployment at boot plus one hour. That is outside every window, so the
# stock command only downloads and the window decides when to apply.
[Service]
ExecStart=
ExecStart=/usr/bin/bootc upgrade --download-only --quiet
```

`ultus-update-window`:

```bash
#!/bin/bash
# Apply a downloaded deployment inside the maintenance window.
#
# The stock timer is left enabled and downloads only. This unit is the only
# place that applies, and it drains the workloads first so a turn is not cut
# mid-write.
set -ouex pipefail

state=/var/lib/ultus
staged_since=$state/staged-since

log() { echo "ultus-update-window: $1" | systemd-cat -t ultus-update-window; }

staged=$(bootc status --format=json | jq -r '.status.staged // empty')
if [[ -z $staged ]]; then
  rm -f "$staged_since"
  log "no staged deployment; nothing to apply"
  exit 0
fi

install -d -m 0755 "$state"
now=$(date +%s)
if [[ -r $staged_since ]]; then
  since=$(cat "$staged_since")
  # A truncated or hand-edited file must not turn into an arithmetic error and
  # a silent no-op, so treat anything that is not a number as "first seen now".
  [[ $since =~ ^[0-9]+$ ]] || since=$now
else
  since=$now
  printf '%s\n' "$now" >"$staged_since"
fi
age=$(( (now - since) / 86400 ))
if ((age >= 14)); then
  log "the staged deployment waited ${age} days; applying and rebooting anyway"
fi

systemctl stop opencode.service hermes.service

rc=0
bootc upgrade --from-downloaded --apply || rc=$?
if ((rc != 0)); then
  log "the apply failed with status ${rc}; restarting the workloads and not rebooting"
  systemctl start opencode.service hermes.service || true
  exit "$rc"
fi

# --apply normally reboots. If it returns, reboot explicitly so the window has
# one outcome rather than two.
log "applied the staged deployment; rebooting into it"
systemctl reboot
```

`ultus-update-window.service`:

```ini
[Unit]
Description=Apply a downloaded deployment inside the maintenance window
RequiresMountsFor=/var/srv
After=var-srv.mount bootc-fetch-apply-updates.service
ConditionPathExists=/run/ostree-booted

[Service]
Type=oneshot
ExecStart=/usr/libexec/ultus/ultus-update-window
TimeoutStartSec=1800
```

`ultus-update-window.timer`:

```ini
[Unit]
Description=Apply the downloaded deployment nightly at 04:00

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true
RandomizedDelaySec=600

[Install]
WantedBy=timers.target
```

- [ ] **Step 6: Enable the units and timers, and run the gates**

Append to the server hook:

```bash
systemctl enable ultus-health.timer ultus-backup.timer \
  ultus-backup-forget.timer ultus-update-window.timer
for unit in ultus-health.timer ultus-backup.timer ultus-backup-forget.timer \
    ultus-update-window.timer bootc-fetch-apply-updates.timer; do
  enabled=$(systemctl is-enabled "$unit" || true)
  [[ $enabled == enabled ]] || {
    echo "$unit is not enabled (got: ${enabled:-nothing})" >&2
    exit 1
  }
done
```

Run: `tests/test-static.sh && tests/test-server-isolation.sh && CONTAINER_RUNTIME=podman tests/lint.sh`
Expected: all pass.

- [ ] **Step 7: Verify every unit parses**

```bash
podman build -f Containerfile.server -t localhost/ultus-atomic-server:dev .
podman run --rm localhost/ultus-atomic-server:dev systemd-analyze verify \
  /usr/lib/systemd/system/ultus-*.service /usr/lib/systemd/system/ultus-*.timer \
  /usr/lib/systemd/system/opencode.service /usr/lib/systemd/system/hermes.service
```

Expected: no output. `systemd-analyze` reports unknown directives as errors, so a typo fails here rather than at first boot.

- [ ] **Step 8: Update the docs and changelog**

`docs/server.md` gains the backup section (both env files' keys, the restore command, that retention is automatic and pruning is weekly), the update section (what the window does, what a failed apply leaves behind, how to opt out by disabling the timer), and the health section. `CHANGELOG.md` gains one line naming the timers.

- [ ] **Step 9: Commit**

```bash
git add modules/server tests/test-static.sh tests/lint.sh docs/server.md CHANGELOG.md
git commit -m "feat: add server health, backup and the update window (#152)"
```

---

### Task 7: Extend the image verifier and the CI filter

**Files:**
- Modify: `tests/verify-image.sh` (the `--server` block at lines 298-331)
- Modify: `.github/workflows/ci.yml:123` (the server path filter)
- Docs: `docs/ci.md`, `docs/testing.md`, `CHANGELOG.md`

**Interfaces:**
- `tests/verify-image.sh --server` additionally asserts: the `agents` user and ranges, the linger flag, every unit this part ships is enabled, every unit passes `systemd-analyze verify`, and the drop-in replaces `--apply`. The loopback-publish rule is asserted by `tests/test-server-isolation.sh`, not here, because that test already parses every unit.
- The server path filter covers the two new test scripts, the two server fixtures, and `tests/vm/`, so a change to any of them rebuilds and boots the image it grades. The fixture path is narrowed to `tests/fixtures/server-` so a desktop fixture does not trigger a server build.

- [ ] **Step 1: Write the failing verifier assertions**

In the `--server` block, after the Flathub check at line 329, add:

```bash
  "$runtime" run --rm "$image" bash -lc '
    getent passwd agents | grep -q ":1000:1000:" &&
    grep -qx "agents:100000:65536" /etc/subuid &&
    grep -qx "agents:100000:65536" /etc/subgid &&
    test -f /var/lib/systemd/linger/agents
  ' || { echo "FAIL the server image lacks the agents user, ranges, or linger flag" >&2; exit 1; }

  # Every unit this part ships must be installed and enabled. A unit disabled by
  # a preset is a server that boots without its role.
  server_units='ultus-data-prepare.service ultus-network.service ultus-tailnet.service
    opencode-env.service hermes-env.service opencode.service hermes.service
    ultus-health.timer ultus-backup.timer ultus-backup-forget.timer
    ultus-update-window.timer'
  for unit in $server_units; do
    "$runtime" run --rm "$image" systemctl is-enabled "$unit" | grep -qx enabled \
      || { echo "FAIL ${unit} is not enabled in the server image" >&2; exit 1; }
  done
  echo "ok   every server unit is enabled"

  "$runtime" run --rm "$image" bash -lc \
    'systemd-analyze verify /usr/lib/systemd/system/ultus-*.service \
       /usr/lib/systemd/system/ultus-*.timer /usr/lib/systemd/system/opencode.service \
       /usr/lib/systemd/system/hermes.service' \
    || { echo "FAIL a server unit does not pass systemd-analyze verify" >&2; exit 1; }
  echo "ok   every server unit passes systemd-analyze verify"

  # The drop-in does not rewrite the vendored unit, so read the drop-in itself.
  if ! "$runtime" run --rm "$image" grep -qx \
      'ExecStart=/usr/bin/bootc upgrade --download-only --quiet' \
      /usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/download-only.conf; then
    echo "FAIL the download-only drop-in is missing or names the wrong command" >&2
    exit 1
  fi
  echo "ok   the stock update only downloads; the window applies"
```

- [ ] **Step 2: Run the verifier to watch it fail**

Run: `tests/verify-image.sh --server localhost/ultus-atomic-server:dev`
Expected: FAIL with `the server image lacks the agents user, ranges, or linger flag`, until Task 2's image is rebuilt.

- [ ] **Step 3: Rebuild and run the verifier**

```bash
podman build -f Containerfile.server -t localhost/ultus-atomic-server:dev .
tests/verify-image.sh --server localhost/ultus-atomic-server:dev
```

Expected: every `ok` line, and the lock comparison stays clean because no package changed.

- [ ] **Step 4: Extend the CI filter**

In `.github/workflows/ci.yml:123`, replace the `regex=` line with:

```bash
regex='^(Containerfile$|Containerfile\.server$|build/|overlay/|modules/|manifests/packages-(common|desktop|server)[.]txt$|manifests/packages-server[.]lock$|tests/verify-image[.]sh$|tests/test-server-isolation[.]sh$|tests/test-server-env[.]sh$|tests/fixtures/server-|tests/vm/)'
```

`tests/vm/` is in the list because Task 8 adds the boot step to `image-server` and the script it runs lives there. `tests/fixtures/server-` is a prefix, not the whole fixtures tree, so a desktop fixture edit does not rebuild the server image.

- [ ] **Step 5: Lint the workflow and run every gate**

Run: `CONTAINER_RUNTIME=podman tests/lint.sh && tests/test-static.sh && tests/test-server-isolation.sh && CONTAINER_RUNTIME=podman tests/test-server-env.sh`
Expected: all pass; `actionlint` accepts the filter change.

- [ ] **Step 6: Update the docs and changelog**

`docs/ci.md` line 8's `image-server` paragraph gains the new path list. `docs/testing.md`'s image-gate row for `verify-image.sh --server` gains the user, linger, unit and drop-in assertions. `CHANGELOG.md` gains one line.

- [ ] **Step 7: Commit**

```bash
git add tests/verify-image.sh .github/workflows/ci.yml docs/ci.md docs/testing.md CHANGELOG.md
git commit -m "test: verify the server role in the image gate (#152)"
```

---

### Task 8: Boot the server in CI and prove the acceptance criteria

**Files:**
- Create: `tests/vm/lib/qemu.sh`
- Create: `tests/vm/boot-smoke-server.sh`
- Modify: `tests/vm/boot-smoke.sh` (use the extracted library)
- Modify: `tests/vm/make-disk.sh` (`SERVER_DISK=1`)
- Modify: `tests/lint.sh` (the two new scripts and the library)
- Modify: `.github/workflows/ci.yml` (the boot step inside `image-server`)
- Docs: `docs/testing.md`, `docs/ci.md`, `CHANGELOG.md`

**Interfaces:**
- `SERVER_DISK=1 tests/vm/make-disk.sh` writes a wheel test account and `$out/qcow2/data.qcow2`, an ext4 filesystem labelled `ultus-data` in a new 8 GiB file.
- `tests/vm/boot-smoke-server.sh [disk.qcow2] [boot.log]` reads the data drive from `SERVER_DATA_DISK`, matching the desktop script's `[disk] [log]` shape. It boots, logs in as the test account, and asserts: `/var/srv` is a mountpoint; `agents` lingers; a container write lands owned by `agents`; the canary reads fail; the listener list is loopback-only; a backup restores real files; the workloads are active again after a guest reboot; and a boot with no data drive leaves no workload container behind.
- The reboot stage needs QEMU to survive a guest reboot and to keep the guest's writes, so the extracted library makes both flags parameters. `QEMU_SNAPSHOT` keeps its current default of 1, and `QEMU_NO_REBOOT` keeps its current default of 1. The server test sets `QEMU_NO_REBOOT=0` and leaves the snapshot on, which keeps the writes for the second boot and still leaves the source disk untouched.
- The boot test pulls both workload images from the guest, so it needs outbound HTTPS to `ghcr.io` and `docker.io`. A runner without it fails at the pull, and the failure dump names the pull error rather than reporting a workload that never started.

- [ ] **Step 1: Extract the QEMU library**

Move `find_ovmf`, the qemu argument list, the serial pipe setup, `wait_for`, `serial_write`, `serial_login` and the cleanup trap from `boot-smoke.sh` into `tests/vm/lib/qemu.sh` as functions over a `disk` list. The argument list takes `QEMU_SNAPSHOT` and `QEMU_NO_REBOOT` with the defaults named above, because the server test reboots the guest and the desktop test does not. Have `boot-smoke.sh` source the library and keep every message string identical, so the desktop job's failure output does not change. Keep the `POST_LOGIN_CMD` hook as well: `tests/test-static.sh:630-643` asserts it exists and is fail-closed. Run `bash -n` on both files, add `tests/vm/lib/qemu.sh` to `tests/lint.sh`'s `bash_scripts`, and commit this alone with `refactor: extract the QEMU boot harness (#152)`.

- [ ] **Step 2: Write the server boot test**

`tests/vm/boot-smoke-server.sh` sources the library and runs serial probes after login, in the shape `boot-smoke.sh` already uses with `DUX_*` markers. Name the server markers `ULTUS_*`:

```bash
serial_write 'mountpoint -q /var/srv && printf "ULTUS_MOUNT:%s\n" ok || printf "ULTUS_MOUNT:%s\n" missing'
serial_write 'printf "ULTUS_LINGER:%s\n" "$(loginctl show-user agents -p Linger --value)"'
serial_write 'sudo -u agents env HOME=/var/lib/agents XDG_RUNTIME_DIR=/run/user/1000 podman run --rm --userns=keep-id -u 1000 -v /var/srv/opencode/share:/state:z ghcr.io/ultus-net/devbox@sha256:8649976df3ebbd38f8b6b323b2a8522cb7de6021e969f836ed57c0cf4ab5e81a sh -c "touch /state/probe" && stat -c "ULTUS_OWNER:%u" /var/srv/opencode/share/probe'
serial_write 'for p in /home /root/.ssh /run/podman/podman.sock /dev/kvm; do sudo -u agents env HOME=/var/lib/agents XDG_RUNTIME_DIR=/run/user/1000 podman run --rm --userns=keep-id -u 1000 --read-only ghcr.io/ultus-net/devbox@sha256:8649976df3ebbd38f8b6b323b2a8522cb7de6021e969f836ed57c0cf4ab5e81a sh -c "test -e $p" && printf "ULTUS_CANARY:%s:readable\n" "$p"; done; printf "ULTUS_CANARY_END:%s\n" ok'
serial_write 'ss -ltnH | awk "{print \$4}" | grep -vE "^(127\.0\.0\.1|\[::1\]):" | grep -q . && printf "ULTUS_LISTEN:%s\n" wide || printf "ULTUS_LISTEN:%s\n" loopback'
```

Assert every marker: `ULTUS_MOUNT:ok`, `ULTUS_LINGER:yes`, `ULTUS_OWNER:1000`, no `ULTUS_CANARY:*:readable` line, `ULTUS_CANARY_END:ok`, `ULTUS_LISTEN:loopback`.

Then, driven from the test rather than the guest:

1. Write `/var/srv/ultus/secrets.env` and `/var/srv/ultus/backup.env` (mode 0600 root, `RESTIC_REPOSITORY=/var/srv/ultus/restic-test`, `RESTIC_PASSWORD_FILE=/var/srv/ultus/restic-password`), create the password file, write a canary file under `/var/srv/repos`, and start `ultus-data-prepare.service opencode-env.service hermes-env.service ultus-backup.service`. Then run `restic restore latest --target /var/srv/restore-check` and assert the canary file is there. A backup that stores an empty tree fails this, and so does one that ran against an unmounted `/var/srv`.
2. Wait for `systemctl is-active opencode.service hermes.service`, with `BOOT_TIMEOUT` as the budget and a `journalctl -u opencode -u hermes` dump plus `podman logs` on timeout.
3. Write `/var/srv/ultus/reboot-marker`, reboot with `systemctl reboot` (QEMU stays up because the test sets `QEMU_NO_REBOOT=0`), wait for the login prompt, log in again, and assert the marker survived and both workloads are active again.
4. Boot the same disk once more with `QEMU_NO_REBOOT=1` and no `SERVER_DATA_DISK`, so `/var/srv` is not a mountpoint. Assert `systemctl is-active --quiet` fails for both workloads, that `podman ps -a --format '{{.Names}}'` names neither `opencode` nor `hermes`, and that `/var/srv/ultus` does not exist on the OS disk.

Expected output: `server boot ok` with every marker at its expected value. Print the log path as the desktop script does.

- [ ] **Step 3: Add `SERVER_DISK=1` to `make-disk.sh`**

When set: add `groups = ["wheel"]` to the `[[customizations.user]]` block, and after the qcow2 build, create `$out/qcow2/data.qcow2` as a sparse 8 GiB file carrying an ext4 filesystem labelled `ultus-data`, owned by the caller. Print the path and verify it with `blkid`, which must print both properties. Refuse `SERVER_DISK=1` together with `NO_TEST_USER=1`, because the server probes need an account with sudo.

- [ ] **Step 4: Run the server boot test locally**

```bash
sudo SERVER_DISK=1 tests/vm/make-disk.sh localhost/ultus-atomic-server:dev
SERVER_DATA_DISK=$PWD/output/qcow2/data.qcow2 QEMU_NO_REBOOT=0 \
  sudo -E tests/vm/boot-smoke-server.sh output/qcow2/disk.qcow2 .vm/server-boot.log
```

Expected: `server boot ok`. On a host without `/dev/kvm` expect the same output much later; set `BOOT_TIMEOUT=2700`. The VM needs outbound HTTPS for the two image pulls.

- [ ] **Step 5: Add the boot step to `image-server`**

There is no separate boot job to copy: `image` runs `boot-smoke.sh` inside itself (`ci.yml:258-272`), after it builds and verifies the image. `image-server` does the same thing, so the boot run goes there and no second image build is paid for.

- Raise `image-server`'s `timeout-minutes` from `120` to `240`.
- Change its install step to `build/install-packages.sh podman qemu-system-x86 qemu-utils ovmf`, as `image` does.
- After the verify step, add the disk build and the boot run:

```yaml
      - name: Build the server disk with a data disk
        run: |
          mkdir -p .cache
          podman save localhost/ultus-atomic-server:ci -o .cache/server-image.tar
          sudo podman load -i .cache/server-image.tar
          sudo SERVER_DISK=1 tests/vm/make-disk.sh localhost/ultus-atomic-server:ci "$GITHUB_WORKSPACE/output"

      - name: Server boot smoke test
        env:
          # TCG on a hosted runner, and this test boots the guest twice.
          BOOT_TIMEOUT: '2700'
          QEMU_ACCEL: tcg
          QEMU_NO_REBOOT: '0'
          SERVER_DATA_DISK: ${{ github.workspace }}/output/qcow2/data.qcow2
        run: |
          sudo -E tests/vm/boot-smoke-server.sh \
            "$GITHUB_WORKSPACE/output/qcow2/disk.qcow2" \
            "$GITHUB_WORKSPACE/.vm/server-boot.log"

      - name: Upload server boot evidence
        if: failure() || cancelled()
        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: server-boot-evidence
          path: |
            .vm/server-boot.log
            .vm/qemu.err
          retention-days: 14
          if-no-files-found: ignore
```

The job stays gated on the `server` filter. No `needs:` change is needed, because `image-server` already depends on `static` and `changes`.

- [ ] **Step 6: Update the docs and changelog**

`docs/testing.md` gains the server boot row, the `SERVER_DATA_DISK`/`QEMU_NO_REBOOT` pair, the note that the reboot stage doubles the runtime, and the outbound-network requirement. `docs/testing.md:143` currently says "The server VM slice is a later part", which this task makes false, so replace that line. `docs/ci.md:8` says `image-server` "does not build a disk, run the boot smoke test, ... export, or publish the artifact", which is only true until this step; keep the export and publish exclusions and drop the disk and boot ones. `CHANGELOG.md` gains one line.

- [ ] **Step 7: Commit**

```bash
git add tests/vm tests/lint.sh .github/workflows/ci.yml docs/testing.md docs/ci.md CHANGELOG.md
git commit -m "test: boot the server image and prove the slice (#152)"
```

---

## Later parts

| Part | Spec sections | Ends with |
| --- | --- | --- |
| 3. Publishing and promotion (#153) | Publishing, Container images | Three published packages, one promotion per host, and a digest delivery path that replaces the workload override file |
| 4. Hardware and retirement (#154) | Migration preconditions, Rollout, First boot and recovery | The vertical slice on the EliteDesk, the UAT row with one deliberate rollback, and `devbox-oc` archived after a verified restic restore |

Part 2 deliberately leaves four things to part 4, because each needs the physical box: the tailnet join with a real key, a real `bootc upgrade --apply` inside the window, a session that resumes across that reboot, and the rollback.

## Self-review

**Spec coverage, part 2:**
- "Rootless containers, no host home, SSH, socket, or devices": Task 4's units and isolation gate, Task 8's canary reads.
- "The `agents` user with a fixed uid and a range": Task 2, with the spike evidence in the decisions table.
- "Units: workloads, env, tailnet, health, backup, window": Tasks 3 to 6.
- "Secrets from the data partition, derived atomically, fail closed": Task 3 and its test.
- "Tailnet join, SSH, serve, key removal": Task 5.
- "Download automatically, apply in a window, restart on failure": Task 6.
- "Extend `verify-image.sh --server` and add the isolation test": Tasks 4 and 7.
- "A write through the mapped volume lands on `/var/srv` owned by `agents`": Task 1 step 4, and Task 8's `ULTUS_OWNER` marker.
- "A restic run stops both workloads, restarts them from `ExecStopPost`, and refuses an unmounted `/var/srv`": Task 6's unit and assertions, Task 8's restore.
- "A session started before a window reboot resumes after it": Task 1 step 5 on the image, and part 4 on hardware. The VM proves a reboot brings the units back; it does not invent a tailnet identity or a staged deployment it cannot download.

**Step scan:** every step names one command or one edit with a checkable result. The two places that name a judgement call (the `$HOME/.local` tmpfs and the Hermes tmpfs set) name the failing log line that decides it.

**Type consistency:** `ultus-*` is the runtime helper prefix, `ultus-atomic` is the build hook prefix, `agents` is the user everywhere, `/var/srv` is the mount everywhere, and `/run/ultus/<workload>.env` is the derived path everywhere.

**Review focus:** the six lines each have a test: isolation (Task 4), env permissions (Task 3), missing disk (Task 8), backup mountpoint (Tasks 6 and 8), window order (Task 6), loopback publish (Tasks 4 and 8).

**Proportion:** this plan is longer than part 1 because it ships eleven units, four timers, one drop-in, six runtime scripts and two new gates; every unit is written out rather than described, so the builder makes no naming or ordering decision of their own.
