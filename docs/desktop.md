# Desktop

The image ships one desktop, and the desktop is replaceable. This page is the
swap procedure: it names every path a replacement touches and what stays put.

## What the desktop is

The desktop is two paths and nothing else:

| Path | Holds |
|---|---|
| `manifests/packages-desktop.txt` | every package only the desktop needs: compositor, shell, greeter, terminal, the shell's helper applications |
| `overlay/desktop/` | every file only the desktop needs: its units, user preset, portal configuration, session and greeter seeds, tmpfiles rule, first-login condition, and its build-time provisioner |

`overlay/desktop/` is copied onto `/` after the shared overlay, so its paths are
the image's paths: `overlay/desktop/usr/lib/systemd/user/x.service` lands at
`/usr/lib/systemd/user/x.service`.

The shared build knows three facts about the module: the subtree may exist, the
manifest path, and the provisioner path `/usr/libexec/dux-atomic/desktop-provision.sh`.
It names no desktop package, unit or command. The provisioner is the module's
build step: it enables the module's repositories, installs
`manifests/packages-desktop.txt` through `build/manifest.sh`, applies the user
presents, asserts the module's own wiring, leaves the repositories disabled and
enables the greeter.

## Swapping the desktop

A swap replaces four paths:

1. `manifests/packages-desktop.txt`: the new package set.
2. `overlay/desktop/`: delete the old subtree and add the new desktop's files at
   the same relative paths.
3. `overlay/desktop/usr/libexec/dux-atomic/desktop-provision.sh`: the new
   desktop's build step. Keep the repository enable, manifest install, preset,
   assertion, repository disable and greeter enable in that order.
4. `tests/test-static.sh` and `docs/first-login.md`: the module's fixtures (the
   product-name list the leak check uses and the first-login cases) and the
   description of what a first login does.

Nothing outside those paths changes. `/etc/dnf/dnf.conf`, the firewalld zone,
the plymouth kargs, `/etc/motd.d`, the os-release identity, the RPM Fusion
repositories and every shared package stay as they are.

## What the suite still proves after a swap

`tests/test-static.sh` and `tests/verify-image.sh` assert the contract, not the
product, so these survive a swap:

- the module ships both halves, and its provisioner installs its manifest;
- no desktop product name appears in the shared build, the shared manifest, the
  `Containerfile` or `tests/verify-image.sh`;
- every user unit in the module refuses root and the greeter account, and is
  ordered before the session;
- one user unit gates first-login setup on an executable condition, has a start
  timeout, and writes a completion marker;
- the greeter seed is JSON that names a session;
- every binding in the module names an absolute unit path;
- in the image: every unit the image's own user preset enables exists and
  passes `systemd-analyze verify`, every binding resolves, the greeter command
  and a session entry name executables, and first-login setup is ordered,
  bounded and idempotent.

A swap that breaks one of those reds the suite, which is the point: the
assertions describe what a desktop has to do, not which desktop is installed.

## Headless

Delete both module paths from a tree and the image builds without a desktop:

```bash
cp -a . /var/tmp/headless && cd /var/tmp/headless
rm -rf overlay/desktop manifests/packages-desktop.txt
podman build --layers -t localhost/ultus-atomic:headless .
```

The shared build skips the subtree copy and the provisioner, and nothing else in
the tree refers to the removed paths. That is the mechanical proof that a swap
is bounded, and it is why the leak assertion in `tests/test-static.sh` exists.

## Trying a desktop before merging

Build a branch that carries the replacement module as `localhost/ultus-atomic:branch`
and boot it with `just boot`. A branch cannot publish a registry image, because
`.github/workflows/ci.yml` gates the `publish` job on `refs/heads/main`, so a
branch is a virtual-machine comparison rather than a `bootc switch` target. When
the replacement wins, the merge replaces the module; the old desktop's files are
deleted in the same change rather than kept as a parallel variant. Two desktops
are never published side by side.
