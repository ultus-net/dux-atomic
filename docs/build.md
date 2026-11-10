# Build

```bash
podman build -t dux-atomic:dev .
```

The `ctx` stage hands `build/`, `manifests/`, and `overlay/` to one build step, so none of them land in the final image. Packages come from `manifests/packages-common.txt`, one name per line. The gaming group pulls in the multilib graphics stack that Steam needs.

The base is pinned in the `Containerfile` as `FROM ghcr.io/ublue-os/base-main:45@sha256:<digest>`. The pin is literal rather than a build argument, because Dependabot's docker ecosystem fetches a file whose name matches `containerfile|dockerfile` and never expands an `ARG` into `FROM`. `tests/test-static.sh` asserts the tag+digest form and rejects a returning `ARG BASE_IMAGE`.

`manifests/packages-common.lock` records the NEVRA and vendor each manifest name resolves to in a built image. `just lock` regenerates it, and `tests/verify-image.sh` fails when a third-party package drifts from it. Fedora packages are left out of that comparison, because they move with the updates repository on every build.

`tests/verify-image.sh` runs `bootc container lint`, `systemd-analyze verify`, the package assertions, and the lock comparison against a built image. `just build` and `just lint-image` wrap the build and the verification.

CI builds the same image and turns it into a qcow2 with bootc-image-builder. See [CI](ci.md) and [Testing](testing.md).
