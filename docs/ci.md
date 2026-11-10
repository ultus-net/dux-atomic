# CI and publishing

`.github/workflows/ci.yml` runs on every pull request, every push to `main`, and manual dispatch. Every action is pinned to a commit SHA, and the job that runs PR code holds only `contents: read`.

- `static` runs `tests/lint.sh`: shell syntax, shellcheck, `tests/test-static.sh`, hadolint, and actionlint. `tests/lint.sh` pins the linter images by digest, and `just check` runs the same script.
- `image` builds the image, runs `tests/verify-image.sh` (`bootc container lint` and `systemd-analyze verify`), generates an SPDX SBOM with syft, builds the qcow2 with bootc-image-builder, and runs `boot-smoke.sh` on QEMU TCG with a 900s boot timeout and a 300s `greetd` grace. The boot test asserts the greeter session through `loginctl` after a serial login, not rendered pixels. It then scans with a digest-pinned trivy container and uploads the report. The scan is report-only until the Fedora base findings are triaged (#3).
- `publish` runs only on `main`, holds the write token and OIDC identity, and runs no repository code. It loads the built artifact, pushes `:sha-<commit>`, signs the digest with cosign keyless OIDC, attests the SBOM, and verifies both the signature and the attestation.
- A `workflow_dispatch` on `main` with `promote` set copies the signed manifest to `:latest` and asserts the registry digest. A failed copy leaves the previous tag, alerts, and needs a human retry. A push never moves `:latest`.
- `static` and `image` are required checks on `main`; a red hosted `image` run blocks merge.
- The `ghcr` environment is the approval hook. Add required reviewers in the repository settings to gate publication.
- The first push creates a private GHCR package. Set the package visibility to public in the package settings if anonymous pulls are wanted.

The SBOM step scans a flattened rootfs with a digest-pinned syft container. syft needed more than 8 GB to scan the docker archive, so the step exports the image first, and it writes the report to a file rather than buffering it in memory.

`just check` mirrors the static gate. `just build`, `just lint-image`, `just disk`, and `just boot` cover the rest.
