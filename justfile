# Local parity for the CI gates. Run `just check` before every push.
# Needs: bash, podman (or docker), and qemu for `just boot`.

set shell := ["bash", "-euo", "pipefail", "-c"]

image := "localhost/dux-atomic:dev"

# Same script and the same pinned linter containers as the CI static job.
check:
    tests/lint.sh

build:
    podman build --layers -t {{image}} .

lint-image:
    tests/verify-image.sh {{image}}

disk:
    sudo tests/vm/make-disk.sh {{image}}

# VIRTIO_GL gives the greeter a render node; without it the session starts but
# the compositor cannot paint.
boot:
    VIRTIO_GL=1 tests/vm/boot-smoke.sh

# The hosted CI runner has no /dev/kvm or render node, so it runs TCG headless.
boot-tcg:
    QEMU_ACCEL=tcg BOOT_TIMEOUT=900 BOOT_GRACE=300 tests/vm/boot-smoke.sh

# Static gate plus an image build and lint. The disk and boot need root and a VM.
ci-local: check build lint-image
