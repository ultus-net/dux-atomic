# Headless server image in ultus-atomic

Status: approved 2026-11-20 (revision 2); revision 3 appends two operator decisions
Date: 2026-11-20
Supersedes: the OS layer of the `devbox-oc` repository, once the server host is installed

Revision 2 incorporates an adversarial review that rejected revision 1. The
material changes are these. The stock updater's `--apply` is replaced with
`--download-only`, because it reboots outside any window. The data-partition
mount targets `/var/srv`, because `/srv` is a symlink. Backups stop the workloads
before restic runs. Secrets move to the data partition, so a rollback cannot drop
them. The package split updates three gates that assume the current manifest.
Tailscale needs `serve` or nothing is reachable. A booted vertical slice gates
publication.

Revision 3 records two operator decisions made after approval. Physical testing
runs on an HP EliteDesk 800 G4 Mini, which serves the GUI run and the headless
run one image at a time. Each host uses one drive holding the OS partitions and
one data partition, because hosts are disposable and rebuilt from backup rather
than repaired in place.

## Intent

One repository owns every immutable Linux host. `ultus-atomic` builds all the
bootc images, `nixos-base` builds all the NixOS hosts, and `devbox-oc` retires
once the server runs from this repo. The desktop, the NVIDIA workstation, and
the always-on development server become three hosts in one image tree, the way
`nixos-base/flake.nix:142` names `tower`, `work-laptop`, `dux-vm`, and
`base-server`.

The hard requirement is that agents run only in containers. Hermes and OpenCode
never execute as host processes, and their containers cannot reach the host
home, SSH keys, the Podman socket, or host devices.

## Why now

`devbox-oc` carries a second OS toolchain for one machine: Fedora CoreOS plus
Ignition, an autorebase unit, its own container-image pipeline, its own digest
pinning, its own tests, and quadlets that duplicate what this repo already does
for the desktop. Every one of those has to be kept working, and the base pin,
kernel, and update story drift independently from this repo's.

`ultus-atomic` already provides the machinery a server needs: a digest-pinned
base, a module seam (`build/common.sh` copies every `modules/*` tree and runs
every `build.d/*.sh` hook), a VM boot test, keyless signing, an SPDX
attestation, SLSA provenance, a blocking vulnerability scan, and a manual
promotion.

The existing headless canary is a package-subtraction test, not a server. It
removes `modules/desktop` and asserts the shared assertions still pass
(`.github/workflows/ci.yml:311`, `tests/verify-headless.sh:25`). It supplies no
users, data disk, workload lifecycle, remote access, backup, update policy, or
publishing. It proves the module seam tolerates a variant. It does not prove a
server works, and this design does not claim otherwise.

## Goals

1. Publish three images: `ultus-atomic` (desktop, name unchanged), `ultus-atomic-server`, and `ultus-atomic-nvidia`.
2. Build the server from a server-safe base plus one module, with no desktop, greeter, Steam, Xfce, Flathub remote, or developer toolchain.
3. Bake Tailscale into every image and enable `tailscaled`.
4. Run OpenCode and Hermes as rootless containers, each mounted on one data-partition subtree.
5. Mount the data partition by filesystem label at `/var/srv`, reach it as `/srv` through the base image's symlink, back it up quiesced with restic, and apply OS updates only inside a maintenance window. A host is disposable: a rebuild restores the data from backup.
6. Enforce all of the above in tests, not prose.
7. Leave the desktop image's installed package set unchanged apart from deliberately adding Tailscale.

## Non-goals

- One container per project or per session. Project choice happens inside the agent.
- Any agent process on the host.
- Ignition, cloud-init, or per-machine OS configuration baked into an image.
- Migrating the running `devbox-oc` install. The EliteDesk is rebuilt.
- A second registry, signing identity, or promotion mechanism.
- Publishing a base or headless image. The CI canary stays a canary.

## Anti-goals

- The server image ships Steam, Xfce, or a compiler: the role split failed.
- An agent container can read the host home, `~/.ssh`, or a Podman socket: the requirement failed.
- Adding a host means copying a 60-line Containerfile: the repo became the thing it replaced.
- A maintenance reboot loses a session that cannot resume: the update policy failed.

## Constraints

- One base pin and one signing path, as today.
- Fedora packages first. The Hermes image runs `:latest` with
  `AutoUpdate=registry` today (`devbox-oc/host/quadlet/hermes.container:51`),
  so pinning it by digest is new work, not a property carried over. The
  non-Fedora waiver carries over.
- Rootless Podman needs a login session for cgroup delegation, plus a runtime
  directory. Quadlet generation does apply `[Install]` at generation time, so
  the build-time objection to quadlets was wrong. Explicit units are still the
  choice below, for parseable isolation assertions and explicit ordering.
- bootc has no Ignition, so the data-disk identity cannot be baked per machine.
- The base image makes `/srv` a symlink to `var/srv`, and systemd refuses to
  mount on a symlinked path. The mount unit targets `/var/srv`.
- The static gate stays the cheapest gate, and it runs before any image builds.

### Test hardware

Physical testing runs on an HP EliteDesk 800 G4 Mini:

- Intel Core i5-8500T, six cores, 35 W T-series, Intel UHD Graphics 630, TPM 2.0, one Intel I219-LM gigabit NIC.
- Two SO-DIMM slots, 32 GB maximum.
- Two M.2 2280 storage slots, one M.2 2230 WLAN slot, and one 2.5 inch SATA bay.
- Two DisplayPort 1.2 outputs as standard.

Two consequences bind the design:

1. The mini is both the GUI test target and the headless test target, one image at a time. The UHD 630 is enough for the generic desktop image, so the greeter, the session, and the first-login units get hardware coverage without the NVIDIA stack. The `nvidia` image still needs the RTX 3070 host, because the mini has no NVIDIA hardware.
2. One drive carries both the OS and the data. `bootc install to-disk --wipe --root-size <size>` writes the OS partitions and leaves the remainder of the drive unallocated, then the operator creates one data partition, makes ext4 on it, and labels it `ultus-data`. The pinned base lists `--root-size` in `bootc install to-disk --help`, so this needs no extra tooling. A host is disposable: a rebuild wipes the drive, so recovery is reinstall plus a restic restore, never a disk migration.

## Decisions the operator made

| Decision | Choice |
| --- | --- |
| Repository split | Two repos: `ultus-atomic` for bootc, `nixos-base` for NixOS. `devbox-oc` retires |
| Agent isolation | Rootless containers, no host home, SSH, socket, or devices, one `/var/srv` subtree per workload |
| Package layout | Split `packages-common.txt` into a server-safe base and a desktop set |
| Data disk | One drive, an OS partition set and one data partition. Mount the data partition by `LABEL=ultus-data` at `/var/srv`; the operator creates it once and no unit does. A host is disposable: recovery is reinstall plus a restic restore |
| Image packaging | One GHCR package per host, each with its own sha tag and promotion |
| Updates | Download automatically, apply and reboot only inside a scheduled maintenance window |
| Tailscale | Baked into every image, `tailscaled` enabled, reachable surfaces published with `tailscale serve` |
| Test hardware | HP EliteDesk 800 G4 Mini, used for both the GUI and the headless run |

## Approaches considered

### Packaging

- **One package per host (chosen).** `ultus-atomic` keeps its name so existing installs keep updating, and `-server` and `-nvidia` join it. A machine's reference never changes meaning, and rollback stays per host.
- One package with role-prefixed tags. One package page, but `latest` becomes ambiguous and the `bootc switch` reference gets easier to mistype.
- Publish the server later. Smallest CI change now, but the server cannot be dogfooded from the registry and retirement waits on a second CI change.

### Image definitions

- **One Containerfile per host (chosen).** `Containerfile`, `Containerfile.nvidia`, and `Containerfile.server` each copy only their own module tree. This follows the existing variant pattern, needs no new build entry point, and the static gate already compares sibling Containerfiles (`tests/test-static.sh:111-122`).
- `hosts/<host>/` plus one Containerfile and a script that assembles a build context. Closest to the NixOS flake shape, but `podman build .` would no longer produce an image, so every doc, CI job, and local command changes.
- One Containerfile with a `MODULES` build argument. Fewest files, but the image's identity becomes a build argument a typo can change silently.

### Rootless workload mechanism

- **Dedicated `agents` system user with linger, workload system units with `User=agents` (chosen).** Rootless Podman works, the start path is explicit, and the units are ordinary files a test can parse. The cost is no quadlet dependency generation, so each unit declares its own ordering and `Restart=`.
- Rootless user quadlets. Cleaner unit syntax, and `[Install]` is applied at generation time, so the earlier build-time objection does not hold. They lose to explicit units only because the isolation test must parse what will actually run.
- Rootful Podman with a non-root container user. Simplest and proven by `devbox-oc`, but it fails the isolation decision.

### Update cadence

- **Download automatically, apply in a nightly window (chosen).** The stock timer's `--apply` is replaced with `--download-only`, and the window drains the workloads before it applies and reboots.
- Leave the stock timer and let it apply. Zero extra code, and it reboots the box at an arbitrary hour, so the decision to schedule the window is not honoured.
- Pin and upgrade by hand. Fully predictable, and the same drift risk.

## Design

### Images

| Image | Containerfile | Modules copied | Extra manifest | Purpose |
| --- | --- | --- | --- | --- |
| `ultus-atomic` | `Containerfile` | `modules/desktop/` | none | Laptop; also the GUI test target on the EliteDesk 800 G4 Mini |
| `ultus-atomic-nvidia` | `Containerfile.nvidia` | `modules/desktop/` | `packages-nvidia.txt` | Desktop on the RTX 3070 host; the mini cannot test it |
| `ultus-atomic-server` | `Containerfile.server` | `modules/server/` | `packages-server.txt` | EliteDesk 800 G4 Mini, headless |

Each Containerfile pins the same base by tag and digest and copies the same
`build`, `manifests`, and `overlay` trees. The static gate gains an assertion
that each Containerfile copies exactly the module its host names, and no other.
`build/common.sh` needs no change, because it already copies whatever module
trees the context carries.

### Package roles

`packages-common.txt` becomes the server-safe base that every image installs.
It keeps containers and Podman, networking, firmware tools, the day-2 update
timer, the diagnostic set, `firewalld`, the dnf defaults, and gains
`tailscale`. The desktop-only groups move to `packages-desktop.txt`: Wayland
portals and session services, audio, graphics and media codecs, the terminal
and Flatpak group, the Xfce fallback, gaming, and the compiler-plus-Node
toolchain. The toolchain moves because the server's development toolchain lives
inside the agent container, not on the host.

`packages-server.txt` carries the host tools only: `restic`.

Three existing gates assume the current split and change with it:

- `tests/test-static.sh:262` requires `nodejs` and `nodejs-npm` in
  `packages-common.txt`, and `tests/verify-image.sh:268` runs `node`, `npm`, and
  a 32-bit mesa check unconditionally. Both move behind the desktop role, or the
  headless canary and the server image fail on a package they do not carry.
- `build/common.sh:73` seeds the Flathub remote into every image. That seeding
  moves into the desktop module hook, so the server carries no Flatpak remote.
- The RPM Fusion release RPMs stay in `build/common.sh:28`, because the NVIDIA
  variant's extra manifest is installed there and `akmod-nvidia` needs the
  repository. The server therefore records those two `@commandline` entries in
  its lock. A lock of exactly those two entries is the expected server result,
  not an empty file.

Tailscale is in the base, so all three images ship it and enable
`tailscaled.service`. Fedora 45 carries `tailscale-0:1.102.5-1.fc45` and
`restic-0:0.19.1-1.fc45` (measured with `dnf5 repoquery` on 2026-11-20). The
server authenticates from `/var/srv/ultus/tailscale-authkey`, mode 0600 owner
root, which the operator places after first boot. A oneshot joins and then
deletes the key, accepts an already-joined node, and never latches on a revoked
key, the shape `devbox-oc/host/bin/oc-tailnet-up:27` already uses. The desktop
authenticates interactively with `tailscale up`.

`tailscaled` runs as root. The base already disables sshd
(`build/common.sh:69`), so the server ships no LAN SSH door.

Loopback publication alone exposes nothing. Two units close that gap, and
without them the box is unreachable:

- `tailscale set --ssh=true`, which authenticates by tailnet identity and needs
  no `authorized_keys`.
- `tailscale serve --bg --https=<port> http://127.0.0.1:<port>` once per
  surface, exactly the three calls in `devbox-oc/host/bin/oc-tailnet:28`.

One rule keeps the tailnet as the only path in: every application port
publishes on `127.0.0.1`, never `0.0.0.0`. A new test parses the module's units
for a `ListenStream=` outside loopback and for a publish that is not loopback.
The walk covers `LLMNR` and `mDNS` as well, because neither is a
`ListenStream=` and neither appears in a unit scan
(`devbox-oc/host/tests/test_no_lan_listener.sh:64`). The VM enumerates the
actual listeners at runtime rather than trusting the module text.

Proof that the split changed nothing for the desktop: build the desktop image
before and after and compare `rpm -qa` as a set. The expected result is the old
set plus `tailscale`, and nothing else. Compare against that expectation, not
against raw equality, or the intentional addition reads as a regression.

The lock gate is per published image. `build/package-lock.sh` records only
packages from non-Fedora origins, so the 24 entries in
`manifests/packages-common.lock` are duxlabs COPR apps and RPM Fusion codecs,
plus the two RPM Fusion release RPMs. A correct server image records exactly
those two `@commandline` release entries. Any codec, Steam package, or COPR app
in the server lock is a split failure the gate catches.

`tests/verify-image.sh` gains a lock-path argument. The NVIDIA image stops
passing `--no-package-lock` (`.github/workflows/ci.yml:297`) once it is
published, so it gets a real lock too.

### Server module

`modules/server/` mirrors `/`, as every module does:

- `usr/lib/systemd/system/var-srv.mount`: `What=/dev/disk/by-label/ultus-data`, `Where=/var/srv`, `Type=ext4`, `Options=defaults,noatime,nofail`, `TimeoutSec=30`. `/srv` is a symlink in the base image, so the mount targets `/var/srv`; `devbox-oc/os/butane/ucore.bu:157` records the same constraint. Workloads carry `RequiresMountsFor=/var/srv`, so a missing data disk stops the agents instead of letting them write to the OS disk.
- `usr/lib/systemd/system/ultus-tailnet.service`: oneshot as root, `RequiresMountsFor=/var/srv`, joins with `tailscale up --auth-key=file:/var/srv/ultus/tailscale-authkey`, runs `tailscale set --ssh=true`, publishes each surface with `tailscale serve --bg`, then deletes the key. A node that is already joined succeeds instead of latching.
- `usr/lib/systemd/system/ultus-network.service`: oneshot as `agents`, creates the `ultus` Podman network once, with `RemainAfterExit=yes`.
- `usr/lib/systemd/system/opencode.service` and `hermes.service`: `User=agents`, `After=` and `Requires=` their env unit, `RequiresMountsFor=/var/srv`, `Restart=on-failure`, and a `--health-cmd` that probes the real endpoint.
- `usr/lib/systemd/system/opencode-env.service` and `hermes-env.service`: `Type=oneshot`, `RemainAfterExit=yes`, read `/var/srv/ultus/secrets.env` and write `/run/ultus/opencode.env` and `/run/ultus/hermes.env` atomically, mode 0600, owner `agents`. Fail closed: no secret, no workload.
- `usr/lib/systemd/system/ultus-health.service` and `.timer`: every minute, runs the containers' health checks and restarts a unit whose process is alive but not answering.
- `usr/lib/systemd/system/ultus-backup.service` and `.timer`: restic at 02:30. It stops both workloads first, runs restic, then starts them from `ExecStopPost` so a failure never leaves the box down, the shape `devbox-oc/os/butane/ucore.bu:217` uses. It refuses to run when `/var/srv` is not a mountpoint.
- `usr/lib/systemd/system/bootc-fetch-apply-updates.service.d/download-only.conf`: replaces `--apply` with `--download-only`, because the base unit applies and reboots (`bootc upgrade --apply --quiet`, `OnBootSec=1h`, `OnUnitInactiveSec=8h`).
- `usr/lib/systemd/system/ultus-update-window.service` and `.timer`: nightly at 04:00, described below.
- `usr/libexec/ultus-atomic/build.d/50-server.sh`: creates the `agents` user and ranges, enables linger, seeds directories, enables the units, and asserts the wiring, the way the desktop hook asserts its own.
- `usr/lib/tmpfiles.d/ultus-server.conf`: `/var/lib/agents`, `/run/user/<uid>`, `/run/ultus` (0750 `root:agents`), and the data-disk subtree parents, with owners.

The module ships no secrets and no default password.

### Rootless agents

- System user `agents` with a fixed uid, home `/var/lib/agents`, and no login shell.
- `/etc/subuid` and `/etc/subgid` entries for `agents` with a 65536 range, so rootless Podman can map container users.
- `loginctl enable-linger agents` is set at build time. Linger is what makes systemd create `/run/user/<uid>` and a delegated cgroup subtree without a login, which Podman's troubleshooting guide requires for rootless cgroup v2.
- Workload units set `HOME=/var/lib/agents` and `XDG_RUNTIME_DIR=/run/user/<uid>`.
- `opencode` mounts `/var/srv/repos` and `/var/srv/opencode` only. `hermes` mounts `/var/srv/hermes` only. Neither mounts `/home`, `/root`, an SSH directory, `/run/podman/podman.sock`, `/run/user/<uid>/podman/podman.sock`, a Docker socket, `/dev`, or the host filesystem.
- Each `podman run` carries `--security-opt no-new-privileges`, `--cap-drop=all`, and a read-only root filesystem with writable state mounts. Ports publish on `127.0.0.1` only.
- Hermes reaches OpenCode by container name on the `ultus` network.

The imported OpenCode image runs as container uid 1000
(`devbox-oc/image/Dockerfile:22`). Rootless mapping would otherwise give it a
subordinate uid, and a directory owned by host `agents` would not be writable.
Every workload therefore passes `--userns=keep-id`, so container uid 1000 maps
to the `agents` uid and the state directories keep one owner. The VM test writes
a file from inside each container and reads it from the host as `agents`; an
ownership bug fails there, not in production.

Units use explicit `podman run` invocations, not generated units, so the image
is reproducible from tracked files and a test can parse what will run.

Two mechanism risks are validated in a VM spike before the unit files are
finalised, because each changes unit content if it fails:

- User namespaces and `subuid`/`subgid` on the pinned base, checked by running a rootless container as `agents` in a booted image.
- Container-name resolution on a rootless custom network. If it fails, the fallback is loopback-published ports on both containers and no shared network.

SELinux stays enforcing. Bind mounts carry a shared label so both containers
reach their subtree, and the install page runs `restorecon -R /var/srv` once
after the data filesystem is initialised. Default Podman seccomp applies, and
no custom profile ships.

The isolation assertion is a new test that parses the shipped unit files. It
runs in the static gate, so it costs seconds, and the VM proves the runtime
side: a canary file under `/home`, an SSH key, both Podman socket paths, and a
device node must each fail to read from inside a container. A non-root identity
check alone proves nothing about those paths.

### Data disk

`var-srv.mount` mounts `LABEL=ultus-data` at `/var/srv`, and `/srv` reaches it
through the base image's symlink. The mount unit cannot use `/srv`, because
systemd refuses to mount on a path that contains a symlink
(`devbox-oc/os/butane/ucore.bu:157`).

The install page tells the operator to size the root partition and create the
data partition once. `bootc install to-disk --wipe --root-size <size> <device>`
writes the OS partitions and leaves the rest of the drive unallocated; the
operator then adds one partition, makes ext4 on it, and labels it `ultus-data`.
No unit creates a partition, formats, relabels, or guesses a device. The VM test
attaches a second qcow2 labelled `ultus-data` as a convenience, which exercises
the same labelled mount, and an unlabelled disk proves the agents stay stopped
instead of writing to the OS disk.

### Secrets

The operator writes `/var/srv/ultus/secrets.env` with mode 0600, owner `root`,
after first boot. It lives on the data disk, not in `/etc`, because rollback
reverts `/etc` to the previous deployment's state and would drop a secret added
since (`docs/install.md:120`). The data disk survives a deployment rollback and
is the one tree the backup covers.

The env units run as root, read that file, and write only the keys each
workload needs into `/var/srv/opencode/env` and `/var/srv/hermes/env`, mode
0600, owner `agents`. Only the derived files reach the workload. A missing
required key fails the unit and the workload does not start.

The keys are the ones `devbox-oc/host/bin/oc-env` and
`devbox-oc/host/bin/hermes-env` already accept: `OPENCODE_PASSWORD`,
`API_SERVER_KEY`, one provider key (`OPENROUTER_API_KEY`,
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or `GOOGLE_API_KEY`), optional
`HERMES_DASHBOARD_BASIC_AUTH_USERNAME`,
`HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`, and
`HERMES_DASHBOARD_BASIC_AUTH_SECRET`, `TELEGRAM_BOT_TOKEN`,
`DISCORD_BOT_TOKEN`, and `TZ`.

Backup credentials stay out of the workload files. `ultus-backup.service`
reads them from its own root-owned `EnvironmentFile=`
(`/var/srv/ultus/backup.env`), so an agent container cannot reach the backup
target. Nothing secret enters the image, the build log, or the repository.

The backup covers the secret files, because the encrypted repository is the
only way to rebuild after a disk failure. The repository password lives in the
operator's password manager, never in the same repo it protects.

### Updates

The base unit cannot be left alone. `bootc-fetch-apply-updates.service` runs
`bootc upgrade --apply --quiet`, and its timer fires at boot plus one hour and
then every eight idle hours. `--apply` finalises the staged deployment, so the
stock timer reboots the box outside any window.

The server ships a drop-in that replaces `--apply` with `--download-only`, which
bootc 1.17.1 supports. `ultus-update-window.timer` fires nightly at 04:00 and
runs a oneshot that does all of this in order:

1. Requires a downloaded deployment, checked with `bootc status --json`.
2. Stops both workloads and waits for them to exit, so a turn is not cut mid-write.
3. Runs `bootc upgrade --from-downloaded --apply`.
4. On failure, records the failure and starts the workloads again. It does not reboot.

A downloaded deployment that has waited 14 days is applied anyway, and the
forced reboot is recorded in the journal. The failure contract is a resumed
session: OpenCode persists session state under `/var/srv/opencode`, and nothing
outside the data disk holds work. That holds only if the container runs with a
service lifecycle. The imported command is plain `opencode serve`
(`devbox-oc/image/Dockerfile:96`), and OpenCode installs restart continuity only
when it is given a lifecycle, so the image must run the service form. A reboot
test asserts that a session started before the window resumes after it.

### First boot and recovery

The first boot has no secrets and no tailnet identity, so nothing remote can
reach the box. A fresh install also has no account, root is locked, and sshd is
disabled (`docs/install.md:9`), so the only way in is the physical boot menu.

The route is the one the install page already uses for the desktop
(`docs/install.md:67`): append `systemd.debug_shell` to the kernel command line
at GRUB, boot to tty9, and work from that root shell. The server page carries
the same steps, then this sequence:

1. Confirm `/var/srv` is the data disk and not a directory on the OS disk.
2. Create `/var/srv/ultus` as `root`, mode 0700.
3. Write `secrets.env` and `backup.env`, then the tailnet auth key.
4. Start `ultus-tailnet.service`, then the workloads, and check the health unit.
5. Record the tailnet address and confirm each served surface answers.

A failed boot has no remote door either. Recovery is the same console:
`bootc rollback --apply` from the emergency shell (`docs/install.md:120`), then
start the workloads. Secrets survive a rollback because they live on the data
disk, not in `/etc`. The UAT row records this sequence actually run on the
EliteDesk, including one deliberate rollback.

### Publishing

Each host image gets its own GHCR package, sha tag, signature, SBOM
attestation, provenance attestation, and verify job. The `promote` dispatch
takes the image name, defaulting to the desktop, and moves only that package's
`:latest` after its verify job is green. The desktop keeps its current name and
`:latest`, so existing installs see no change.

The CI build becomes a matrix over the three Containerfiles. Every per-image
artifact name and output must carry the matrix key: the current singleton
`packages-common.lock`, digest, SBOM, and signature paths
(`.github/workflows/ci.yml:201`, `:261`, `:374`) collide the moment two images
share a job. The nested-VM boot test runs for the desktop and the server.

`.github/workflows/repin-base.yml:114` rewrites only `Containerfile` and
`Containerfile.nvidia`. It gains `Containerfile.server`, with a static test
that every Containerfile carries the same base digest, so the one-base
constraint is enforced rather than remembered.

Where the trust chain ends is recorded, not implied. `docs/known-gaps.md:18`
states that no container policy ships and the host does not verify signatures,
so an unattended server applies whatever the registry serves. Either that gap
closes before the server enables automatic application, or the limitation is
stated on the install page.

### Container images

The OpenCode container image moves from `devbox-oc/image/` to
`containers/opencode/` in this repo, with its own workflow and a recorded digest
file.

The delivery path for a new digest is specified, because a digest baked into the
OS image would force an OS rebuild for every OpenCode release, which is the
coupling this split exists to avoid. `containers/opencode/digest` holds the
pinned digest. A host-side `ultus-workload-update.service` reads that file from
a tracked path on the data disk or fetches the published tag, pulls the image,
and rewrites the digest the units use, then restarts the workload. The update
actor is root on the host, never an agent. The runbook records the manual
equivalent, as `devbox-oc/docs/runbook.md:199` does today.

Hermes is pinned by digest as new work. Today it runs
`nousresearch/hermes-agent:latest` with `AutoUpdate=registry`
(`devbox-oc/os/butane/build.sh:14`, `devbox-oc/host/quadlet/hermes.container:51`),
which is the opposite of a pin. It joins the same digest file and the same
update path.

### Tests

| Gate | Assertion |
| --- | --- |
| `tests/test-static.sh` | Each Containerfile pins the base, copies only its host's module, and no other; every Containerfile carries the same base digest; the server manifest names no desktop or gaming package; the agents user, ranges, linger, and unit contract appear in the module |
| `tests/test-server-isolation.sh` (new) | Parses shipped units for `User=agents`, `--userns=keep-id`, `no-new-privileges`, `cap-drop=all`, and fails on `/home`, `~/.ssh`, either Podman socket, `/dev`, `--privileged`, `--network=host`, `--pid=host`, `--ipc=host`, `--userns=host`, an added capability, or an unconfined security option. It must reject every adversarial mount spelling `tests/test-agent-container.sh:32` already contains (`--volume=/home`, `-v/home:/host`, `--mount=type=bind,source=/home,...`, continuation lines) |
| `tests/verify-image.sh --server` | Desktop units and packages absent; `var-srv.mount`, `ultus-tailnet.service`, the health, backup, and window timers, and the env units present; `systemd-analyze verify` clean; `tailscale` and `restic` installed; no Flathub remote |
| `tests/vm/boot-smoke.sh --server` | Boots with a second qcow2 labelled `ultus-data`; `/var/srv` mounted and `/srv` resolves through it; a container writes a file that the host reads as `agents`; reads of canary home, SSH, socket, and device paths fail; the runtime listener list is loopback-only; a session started before a window reboot resumes after it; backup restores to a scratch directory; a missing second disk leaves the agents stopped; rollback restores a working deployment |
| Desktop regression | `rpm -qa` equals the old set plus `tailscale`, and nothing else |

The server VM boot test runs as its own CI job on TCG, in parallel with the
desktop job and with its own timeout. Hosted runners have no `/dev/kvm`, so the
job is slow by design, and a separate job keeps it from queueing behind or
blocking the desktop boot.

The headless canary is retargeted, not kept as a desktop twin. With the split,
the base is the server base, so the canary asserts the base image's shared
behaviour and the absence of every module path. It no longer runs the desktop's
node, npm, and 32-bit mesa checks, which move behind the desktop role.

## Rollout

1. Split the manifest and move the role-gated checks; prove the desktop set is the old set plus Tailscale.
2. Add `Containerfile.server` and extend the repin workflow and the one-base static test.
3. Spike the risky mechanisms in a VM: linger, rootless from a system unit, `keep-id` writes, container-name resolution.
4. Add the server module: units, agents user, `/var/srv` mount, tailnet join and serve, secrets, health, quiesced backup.
5. Add the isolation test and the server image verifier.
6. Add the server VM boot test with a labelled second disk, then run the vertical slice below.
7. Turn CI into a matrix and add per-host publish and promotion.
8. Move the OpenCode container image into `containers/opencode/`, pin Hermes by digest, and add the workload update path.
9. **Gate.** The vertical slice must pass on a booted server before anything is published: install, join Tailscale, serve a healthy client through the tailnet, write through the mapped volume, restore a quiesced backup, survive an in-window update, fail safely with the disk absent, and roll back.
10. Install the EliteDesk, record a UAT row, then archive `devbox-oc` with a pointer in its README.

### Migration preconditions

The existing `devbox-oc` disk is labelled `data`, and the new mount expects
`ultus-data`. The rebuild wipes the drive, so the data partition is created
again and filled from the backup, never relabelled in place. Before the rebuild:

1. Take a restic backup on the running `devbox-oc` and verify it by restoring to a scratch path.
2. Confirm the restore contains the OpenCode and Hermes state, not an empty tree.
3. Record the drive's size and the space the data needs, so `--root-size` leaves room for the data partition.
4. Install with `bootc install to-disk --wipe --root-size <size>`, create the data partition in the remaining space, make ext4 on it, label it `ultus-data`, and restore the backup into it.
5. Never point the install at the existing data partition expecting it to survive: `--wipe` erases the whole device.

Archiving `devbox-oc` needs more than one UAT row. It needs a verified restore
of that disk and a server that has survived one update window.

## Open items for the builder

- Choose the `agents` uid and the `subuid`/`subgid` base, and confirm `useradd` accepts a fixed range at build time.
- Confirm `--userns=keep-id` gives container uid 1000 write access to the state directories under `/var/srv`, and record the ownership check that proves it.
- Confirm the OpenCode container supports the service lifecycle form that restart continuity needs, and name the exact command.
- Decide where the workload digest file lives on the host and who may change it.
- Choose the restic repository variables and the retention policy; both come from `/var/srv/ultus/backup.env`.
- Confirm the desktop's compiler and Node move does not break the dotfiles bootstrap, and file that change against #96 if it does.
- Decide the exact server host name and whether the NVIDIA image ships in the same change or after the server.
