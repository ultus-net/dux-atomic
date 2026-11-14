# Project-scoped rootless agent container

This page describes the disposable, project-scoped, rootless Podman profile used to run agents safely for a repository.

Key points
- The container mounts only the project directory, writable, at `/work` inside the container, and starts there. The host path is not mounted.
- The container receives an isolated HOME and XDG cache stored in a temporary directory under `$TMPDIR` (default `/tmp`); the host home and SSH directory are not mounted. A foreground run deletes that directory afterwards. A `--detach` run prints it instead, because the container keeps reading it after the script exits.
- No host Podman or Docker socket is exposed. That means the container cannot control sibling containers or the host Podman service.
- The profile runs unprivileged, defaults to --rm, does not use --privileged, and avoids --network=host and host PID namespaces by default.

Why `/work` rather than the host path: a bind mount makes Podman create any missing parent directory of the container path. Mounting at `/home/<user>/project` would create that scaffolding inside the image, so a check that the host home is absent would pass for the wrong reason or fail for no real reason.

Escape hatch (AGENT_CONTAINER_EXTRA)

The escape hatch is deny-by-default. Only a small allowlist of extra flags is accepted; everything else is rejected. This guarantees the profile cannot be weakened by a surprising flag form.

Allowed extras (summary)
- --detach or -d
- --name <name> (name must match [A-Za-z0-9][A-Za-z0-9_.-]*)
- -e KEY or -e KEY=VALUE, --env KEY or --env KEY=VALUE (KEY must be a valid env var name)
- --network none|bridge|slirp4netns only
- --memory, --cpus, --pids-limit with numeric or size values
- --read-only, --cap-drop <value>
- --security-opt no-new-privileges only
- --tmpfs <path> limited to paths under /tmp
- -w/--workdir only as `/work` or a path under it

Anything else (for example -v, --volume, --mount, --privileged, --pid, --ipc, --userns, --device, --cap-add, unknown flags) is rejected. `--tmpfs` is the only mount-shaped extra, and it creates an in-container temporary filesystem under `/tmp`, never a host path. This is the intended guarantee: the only way to bind a host path or expose host devices is to remove the escape hatch entirely.

Usage example (dry run):

AGENT_CONTAINER_DRY_RUN=1 build/agent-container.sh localhost/dux-atomic:dev /path/to/project -- --name test-agent --network=none

See also
- `docs/research/2026-11-14-agent-container.md` — the recorded run and its output
- `docs/developer-tooling.md` — why cloud CLIs are an operations container
