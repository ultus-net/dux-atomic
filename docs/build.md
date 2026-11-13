# Build

```bash
podman build -t dux-atomic:dev .
```

The `ctx` stage hands `build/`, `manifests/`, and `overlay/` to one build step, so none of them land in the final image. Packages come from `manifests/packages-common.txt`, one name per line. The gaming group pulls in the multilib graphics stack that Steam needs.

The base is pinned in the `Containerfile` as `FROM quay.io/fedora/fedora-bootc:45@sha256:<digest>`. Fedora signs that image's kernel and modules, so a Secure Boot machine trusts the chain with no per-machine MOK enrollment, and the image carries no desktop environment to strip (#59). A Universal Blue desktop image would inherit both the enrollment machinery and a full KDE or GNOME session; replacing the kernel with one Universal Blue signs (`ublue-os/main/build_files/install.sh:46`) is what forces the enrollment.

Because the base has no desktop, `manifests/packages-common.txt` names every package the session needs, grouped by reason. The quality-of-life the Universal Blue base provided is restored that way rather than by installing Universal Blue's own packages: `ublue-os-just` exists mainly to enroll the Universal Blue key, and `ublue-setup-services`, `ublue-motd`, and `ublue-os-signing` assume a boot chain this image does not have. `build/common.sh` installs `dnf5-plugins` before enabling the Dux COPRs, adds the `negativo17` multimedia repository for `steam`, disables `sshd.service` (enabled by default on the Fedora base), seeds the Flathub remote, and leaves the Dux COPRs disabled afterwards. Updates come from `bootc-fetch-apply-updates.timer`, which the base enables through `86-bootc-standard.preset`.

The pin is literal rather than a build argument, because Dependabot's docker ecosystem fetches a file whose name matches `containerfile|dockerfile` and never expands an `ARG` into `FROM`. `tests/test-static.sh` asserts the tag+digest form, rejects a returning `ARG BASE_IMAGE`, and requires every `FROM` line to be either `scratch` or a tag+digest pin, so the NVIDIA variant's own base in #40 is covered too. A same-tag digest bump reaches the repo as a Dependabot pull request, unless the digest-only-update suppression experiment is enabled for this repo.

`manifests/packages-common.lock` records the NEVRA and the package `%{from_repo}` for every installed package whose origin repository is not a Fedora repository, one line per NEVRA; a multilib name such as `mangohud` contributes two lines. It is a drift gate, not an install pin: the build installs by name from live repositories, and the gate compares the recorded set against the image afterwards. `tests/verify-image.sh` compares the whole recorded set to the generator's measurement (the generator drops `+git` builds), so an unpinned third-party rebuild — including a transitive one — is caught. Fedora-origin packages are excluded so a Fedora updates bump does not red the gate. Run `just lock` after changing the manifest, and whenever the gate reports third-party drift, whether a base bump or a COPR rebuild.

`tests/verify-image.sh` runs `bootc container lint`, `systemd-analyze verify`, the package assertions, and the lock comparison against a built image. `just build` and `just lint-image` wrap the build and the verification.

CI builds the same image and turns it into a qcow2 with bootc-image-builder. See [CI](ci.md) and [Testing](testing.md).
