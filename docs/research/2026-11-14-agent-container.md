# Agent container run record (2026-11-14, issue #71)

Status: evidence record. Every fenced block is a command that ran on this host
followed by its output. Paths are shortened only where noted.

The image is the local development build of this branch's tree, which carries
the tooling layer:

```
$ podman run --rm localhost/dux-atomic:dev node --version
v22.23.1
$ podman image inspect localhost/dux-atomic:dev --format '{{.Id}}'
fb0131b69df0d8672860ef7324cb6f2f74262958ad768a06ade00bc515af2756
```

## Isolation, measured from inside the container

A project directory with one file, run through the profile. The command is a
`/bin/sh -c` so nothing in the probes can be expanded by the host shell.

```
$ mkdir -p .scratch/agent-demo
$ printf 'hello\n' > .scratch/agent-demo/file.txt
$ build/agent-container.sh localhost/dux-atomic:dev "$PWD/.scratch/agent-demo" -- /bin/sh -c '
    printenv HOME; printenv XDG_CACHE_HOME; pwd; ls -la; id -un
    if [ ! -e /home/csh ]; then echo NO_HOST_HOME; else echo HOST_HOME_PRESENT; fi
    if [ ! -e /home/agent/.ssh ]; then echo NO_SSH_DIR; else echo SSH_DIR_PRESENT; fi
    if [ ! -S /run/user/1000/podman/podman.sock ]; then echo NO_PODMAN_SOCKET; else echo PODMAN_SOCKET_PRESENT; fi'
/home/agent
/tmp/agent-cache
/work
total 4
drwxr-xr-x 1 csh  csh  16 Nov 14 00:02 .
drwxr-xr-x 1 root root 32 Nov 14 00:06 ..
-rw-r--r-- 1 csh  csh   6 Nov 14 00:02 file.txt
csh
NO_HOST_HOME
NO_SSH_DIR
NO_PODMAN_SOCKET
```

`HOME` and `XDG_CACHE_HOME` are the container's own values, printed by
`printenv` with no host expansion. The project is at `/work` and holds exactly
the one file. `id -un` prints `csh` because `--userns=keep-id` maps the host uid
into the rootless namespace; isolation here comes from the mount set, not from a
different uid.

The project is mounted at `/work`, not at its host path. A bind mount makes
Podman create the missing parents of the container path, so a same-path mount
under `/home/csh/...` created that scaffolding inside the image and the
`NO_HOST_HOME` probe silently stopped being a check at all.

## Mount and namespace set, measured from outside

A detached run, inspected while it slept. `--detach` and `--name` are on the
escape-hatch allowlist.

```
$ AGENT_CONTAINER_EXTRA="--detach --name agent-probe" build/agent-container.sh \
    localhost/dux-atomic:dev "$PWD/.scratch/agent-demo" -- /bin/sleep 60
6562825146e0a4071c0556842a03dd6aafe6fa4590b76957d6f2ff375bd87634
Temp kept: /tmp/opencode/agent-container.8nmr
$ podman inspect agent-probe --format '{{range .Mounts}}HOST={{.Source}} -> CONTAINER={{.Destination}} RW={{.RW}}{{"\n"}}{{end}}'
HOST=<worktree>/.scratch/agent-demo -> CONTAINER=/work RW=true
HOST=/tmp/opencode/agent-container.8nmr/home/agent -> CONTAINER=/home/agent RW=true
HOST=/tmp/opencode/agent-container.8nmr/tmp/agent-cache -> CONTAINER=/tmp/agent-cache RW=true
$ podman inspect agent-probe --format 'PRIVILEGED={{.HostConfig.Privileged}} NETWORK={{.HostConfig.NetworkMode}} PID={{.HostConfig.PidMode}} USERNS={{.HostConfig.UsernsMode}}'
PRIVILEGED=false NETWORK=pasta PID=private USERNS=private
$ podman rm -f agent-probe
```

Three mounts, all writable, all deliberate: the project at `/work`, and the
temporary home and cache. No host home, no SSH directory, no socket. The network
is `pasta`, which is rootless Podman's default, not the host namespace.

A detached container keeps reading its mounted home after the script exits, so
that run prints the temporary tree instead of deleting it. A foreground run
deletes it:

```
$ ls -d /tmp/opencode/agent-container.* | wc -l
13
$ build/agent-container.sh localhost/dux-atomic:dev "$PWD/.scratch/agent-demo" -- /bin/true
$ ls -d /tmp/opencode/agent-container.* | wc -l
13
```

The count is unchanged, so the foreground run left nothing behind. The 13
directories are debris from earlier runs of an earlier version of the script,
which `exec`ed Podman and so never reached its own cleanup.

## What this record does not prove

- No agent CLI ran inside the container. The probes are `/bin/sh` builtins,
  `printenv`, and `ls`, so the record shows the mount environment, not that a
  specific agent tool works in it.
- The escape hatch was exercised only through `--detach` and `--name`. The
  red-path evidence for rejected flags is in `tests/test-agent-container.sh`.
- Only one image was tested: the local development build named above.
