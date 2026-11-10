# Local parity for the CI gates. Run `just check` before every push.
# Needs: bash, podman, shellcheck, and qemu for `just boot`.

set shell := ["bash", "-euo", "pipefail", "-c"]

image := "localhost/dux-atomic:dev"
hadolint := "docker.io/hadolint/hadolint:v2.12.0"

check:
    bash -n build/common.sh tests/test-static.sh tests/vm/boot-smoke.sh tests/vm/make-disk.sh
    sh -n overlay/usr/libexec/dux-atomic/needs-setup.sh
    shellcheck --severity=warning build/common.sh tests/test-static.sh tests/vm/boot-smoke.sh tests/vm/make-disk.sh overlay/usr/libexec/dux-atomic/needs-setup.sh
    bash tests/test-static.sh
    podman run --rm -v "$PWD:/mnt:ro" -w /mnt {{hadolint}} hadolint --failure-threshold warning Containerfile

build:
    podman build --layers -t {{image}} .

lint-image:
    podman run --rm {{image}} bootc container lint
    podman run --rm {{image}} systemd-analyze verify /usr/lib/systemd/system/dux-atomic-greeter-defaults.service /usr/lib/systemd/user/dux-atomic-desktop.service /usr/lib/systemd/user/dux-atomic-dms-defaults.service

disk:
    sudo tests/vm/make-disk.sh {{image}}

boot:
    tests/vm/boot-smoke.sh

# The hosted CI runner has no /dev/kvm, so the workflow runs the boot test on TCG.
boot-tcg:
    QEMU_ACCEL=tcg BOOT_TIMEOUT=1800 BOOT_GRACE=600 tests/vm/boot-smoke.sh

ci: check build lint-image
