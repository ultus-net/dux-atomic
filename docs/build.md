# Build

```bash
podman build -t dux-atomic:dev .
```

The `ctx` stage hands `build/`, `manifests/`, and `overlay/` to one build step, so none of them land in the final image. Packages come from `manifests/packages-common.txt`, one name per line. The gaming group pulls in the multilib graphics stack that Steam needs.

The base is pinned in the `Containerfile` as `FROM ghcr.io/ublue-os/base-main:45@sha256:<digest>`. The pin is literal rather than a build argument, because Dependabot's docker ecosystem fetches a file whose name matches `containerfile|dockerfile` and never expands an `ARG` into `FROM`. `tests/test-static.sh` asserts the tag+digest form, rejects a returning `ARG BASE_IMAGE`, and fails if any base `FROM` line is unpinned. A same-tag digest bump reaches the repo as a Dependabot pull request, unless the digest-only-update suppression experiment is enabled for this repo.

`manifests/packages-common.lock` records the NEVRA and vendor every manifest name resolves to in a built image, one line per NEVRA, so a multilib name such as `mangohud` contributes two. It is a drift gate, not an install pin: the build installs by name from live repositories, and the gate compares the result afterwards. `tests/verify-image.sh` fails when a line whose vendor is not `Fedora Project` drifts, which is how an unpinned COPR or `negativo17` rebuild is caught. Fedora lines are left out of that comparison, because they move with the updates repository on every build. Packages the manifest names pull in transitively are outside the lock; [known-gaps](known-gaps.md) records that and the `%{VENDOR}` limitation. Run `just lock` after changing the manifest, and whenever the gate reports third-party drift, whether a base bump or a COPR rebuild.

`tests/verify-image.sh` runs `bootc container lint`, `systemd-analyze verify`, the package assertions, and the lock comparison against a built image. `just build` and `just lint-image` wrap the build and the verification.

CI builds the same image and turns it into a qcow2 with bootc-image-builder. See [CI](ci.md) and [Testing](testing.md).
