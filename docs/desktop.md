# Desktop

The image ships one desktop, and the desktop is replaceable. This page is the
swap procedure: it names every path a replacement touches and what stays put.

## What the desktop is

The desktop is two paths and nothing else:

| Path | Holds |
|---|---|
| `manifests/packages-desktop.txt` | every package only the desktop needs: compositor, shell, greeter, terminal, the shell's helper applications |
| `modules/desktop/` | every file only the desktop needs: its units, user preset, portal configuration, session and greeter seeds, tmpfiles rule, first-login condition, and its build-time step |

`modules/desktop/` mirrors `/`, and the shared build copies each `modules/*/`
tree onto `/` after the shared overlay. Its paths are therefore the image's
paths: `modules/desktop/usr/lib/systemd/user/x.service` lands at
`/usr/lib/systemd/user/x.service`. Modules live outside `overlay/` so the shared
overlay copy cannot leave a module tree behind as a stray `/desktop`, and a swap
cannot accidentally keep half of the old desktop.

The shared build knows two facts about modules: any `modules/*/` tree is copied
onto `/`, and any module may ship build steps under
`/usr/libexec/ultus-atomic/build.d/`, which it runs in name order. It names no
desktop package, unit or command. The desktop's step is
`modules/desktop/usr/libexec/ultus-atomic/build.d/50-desktop.sh`: it enables the
module's repositories, installs `manifests/packages-desktop.txt` through
`build/manifest.sh`, applies the user presets, asserts the module's own wiring,
disables the repositories from an exit trap and enables the greeter.

## Swapping the desktop

A swap replaces four paths:

1. `manifests/packages-desktop.txt`: the new package set.
2. `modules/desktop/`: delete the old subtree and add the new desktop's files at
   the same relative paths.
3. `modules/desktop/usr/libexec/ultus-atomic/build.d/50-desktop.sh`: the new
   desktop's build step. Enable its repositories, install its manifest, apply its
   presets, assert its wiring, then enable its greeter, with an exit trap that
   disables the repositories on every path, so a failed build cannot commit a
   layer with third-party repositories enabled.
4. `tests/test-static.sh` and `docs/first-login.md`: the module's fixtures (the
   product-name list the leak check uses and the first-login cases) and the
   description of what a first login does.

Nothing outside those paths changes. `/etc/dnf/dnf.conf`, the firewalld zone,
the plymouth kargs, `/etc/motd.d`, the os-release identity, the RPM Fusion
repositories and every shared package stay as they are.

## What the suite still proves after a swap

`tests/test-static.sh` and `tests/verify-image.sh` assert the contract, not the
product, so these survive a swap:

- the module ships both halves, and its build step installs its manifest;
- no desktop product name appears in the shared build, the shared manifest, the
  `Containerfile` or `tests/verify-image.sh`;
- every user unit in the module refuses root and the greeter account, and is
  ordered before the session;
- one user unit gates first-login setup on an executable condition, has a start
  timeout, and writes a completion marker;
- the greeter seed is JSON that names a session;
- every binding in the module names an absolute unit path;
- in the image: every unit the image ships outside a package, and every unit its
  own user preset enables, passes `systemd-analyze verify`; every binding
  resolves; the greeter command and a session entry name executables; and
  first-login setup is gated on an executable condition, ordered before the
  session, bounded by a start timeout, and marks completion.

A swap that breaks one of those reds the suite, which is the point: the
assertions describe what a desktop has to do, not which desktop is installed.

## Headless

Delete both module paths from a tree and the image builds without a desktop:

```bash
cp -a . /var/tmp/headless && cd /var/tmp/headless
rm -rf modules/desktop manifests/packages-desktop.txt
podman build --layers -t localhost/ultus-atomic:headless .
```

The shared build copies no module and runs no build step, and nothing else in
the tree refers to the removed paths. That is the mechanical proof that a swap
is bounded, and it is why the leak assertion in `tests/test-static.sh` exists.

CI runs that build in the `headless` job whenever a path the seam reads changes.
The job saves `manifests/packages-desktop.txt` before deleting it, builds the
tree, and runs `tests/verify-headless.sh`, which asserts the image carries
neither module path and none of the manifest's package names.

## Trying a desktop before merging

Build a branch that carries the replacement module as `localhost/ultus-atomic:branch`
and boot it with `just boot`. A branch cannot publish a registry image, because
`.github/workflows/ci.yml` gates the `publish` job on `refs/heads/main`, so a
branch is a virtual-machine comparison rather than a `bootc switch` target. When
the replacement wins, the merge replaces the module; the old desktop's files are
deleted in the same change rather than kept as a parallel variant. Two desktops
are never published side by side.
