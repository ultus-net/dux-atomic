# Local parity for the CI gates. Run `just check` before every push.
# Needs bash and podman; the static gate also accepts docker. `just boot` needs qemu.

set shell := ["bash", "-euo", "pipefail", "-c"]

image := "localhost/dux-atomic:dev"

# Same script and the same pinned linter containers as the CI static job.
check:
    tests/lint.sh

# Signature policy acceptance and rejection on a throwaway local registry.
# Needs podman, skopeo, cosign and a free 127.0.0.1:5000.
signing:
    tests/test-signing.sh

build:
    podman build --layers -t {{image}} .

lint-image:
    tests/verify-image.sh {{image}}

# Regenerate the third-party package lock from a built image. The temp file
# keeps a failed run from truncating the tracked lock, and the trap removes it.
# just has no `$$` escape: the `$` goes to bash unchanged.
lock:
    @tmp=manifests/packages-common.lock.tmp; trap 'rm -f "$tmp"' EXIT; build/package-lock.sh {{image}} > "$tmp"; mv "$tmp" manifests/packages-common.lock

disk:
    sudo tests/vm/make-disk.sh {{image}}

# VIRTIO_GL gives the guest a GL path and the script asserts the render node.
# Without it the session starts, but pixel correctness is unproven.
boot:
    VIRTIO_GL=1 tests/vm/boot-smoke.sh

# The hosted CI runner has no /dev/kvm, so it runs TCG headless.
boot-tcg:
    QEMU_ACCEL=tcg BOOT_TIMEOUT=900 BOOT_GRACE=300 tests/vm/boot-smoke.sh

# Static gate plus an image build and lint. The disk and boot need root and a VM.
ci-local: check build lint-image
