# Dotfiles bootstrap hand-off (2026-11-14, issue #70)

Status: hand-off record. The run is **not** proof. Every fenced block below is a
command that ran on this host with its output, and the last two sections name
what remains for an operator.

## What the plan asks for

`docs/superpowers/plans/2026-11-14-tooling-and-platform-roadmap.md` task 2 asks
for a booted image, a test account, the dotfiles `install/bootstrap.sh --only 20`
run as that account, and `npm ls -g`, `brew --version`, and `distrobox list`
recorded with the versions.

## What ran

The toolchain is present, so nothing here is blocked on the image itself:

```
$ qemu-system-x86_64 --version
QEMU emulator version 11.1.2
Copyright (c) 2003-2026 Fabrice Bellard and the QEMU Project developers
$ podman info --format '{{.Host.Security.Rootless}}'
true
```

The image builds from this tree:

```
$ podman build --layers -t localhost/dux-atomic:dev .
...
Successfully tagged localhost/dux-atomic:dev
$ podman image inspect localhost/dux-atomic:dev --format '{{.Id}}'
sha256:833793b11417c9f5ab0de708bc449855490a4d06e7558a6771f5f6047a94de09
```

The static gate passes on the same tree:

```
$ CONTAINER_RUNTIME=podman bash tests/lint.sh
...
static checks passed
$ echo $?
0
```

## Where it stops

`tests/vm/make-disk.sh:4` states the requirement: it must run as root, because
`bootc-image-builder` writes loop devices, and the image must already be in
rootful podman storage. Moving a rootless build across needs `sudo`:

```
$ podman save localhost/dux-atomic:dev | sudo podman load
[workflow-guard] Blocked: 'podman save localhost/dux-atomic:dev | sudo podman load' is an sudo with password prompt and will hang non-interactive agent execution.
```

That guard exists so an agent cannot block on a password prompt, so the disk
build and every step after it are outside an agent session. Nothing in this
record should be read as a bootstrap result: no VM booted, no test account
logged in, and the dotfiles stage never ran.

## The operator sequence that finishes it

Run as a user with `sudo`, in this repository:

1. Copy the built image into rootful storage:
   `podman save localhost/dux-atomic:dev | sudo podman load`
2. Build the disk: `sudo tests/vm/make-disk.sh localhost/dux-atomic:dev output`
3. Boot it and log in as the test account:
   `tests/vm/boot-smoke.sh output/qcow2/disk.qcow2 .vm/boot.log`
4. Run the dotfiles stage in that session, from the dotfiles checkout:
   `install/bootstrap.sh --only 20`
5. Capture `npm ls -g`, `brew --version`, and `distrobox list` with their
   versions, then replace this hand-off with a run record.

Steps 3 and 4 can be combined: `tests/vm/boot-smoke.sh` now accepts
`POST_LOGIN_CMD`, which sends one literal command to the logged-in session and
writes `DUX_POST_BEGIN` and `DUX_POST_END:<status>` around its output, so the
stage's transcript lands in `.vm/boot.log` with the boot evidence. The hook is
off by default and does not change a plain boot.

## What is known to be wrong with the bootstrap

Nothing yet. There is no failure to hand off, because the stage never ran. If
step 4 does fail, the fix belongs in the
[dotfiles repository](https://github.com/ultus-net/dotfiles), and the failure
belongs in this record with the command and its output.

## What this record does not prove

- That `install/bootstrap.sh --only 20` runs on this image, that `npm ls -g`
  lists `opencode-ai`, that `brew --version` answers, or that `distrobox list`
  answers. All four are untested here.
- That the built image boots at all on QEMU. Only the build and the static gate
  ran against it.
- That the local image id above matches the digest the hosted `image` job
  builds. The build was local and untagged by digest.
