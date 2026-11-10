# Build

```bash
podman build -t dux-atomic:dev .
```

The `ctx` stage hands `build/`, `manifests/`, and `overlay/` to one build step, so none of them land in the final image. Packages come from `manifests/packages-common.txt`, one name per line.

`tests/verify-image.sh` runs `bootc container lint` and `systemd-analyze verify` against a built image. `just build` and `just lint-image` wrap both steps.

CI builds the same image and turns it into a qcow2 with bootc-image-builder. See [CI](ci.md) and [Testing](testing.md).
