#!/usr/bin/env bash
# Build a bootable qcow2 from a local image with bootc-image-builder.
#
# Must run as root, because bootc-image-builder writes loop devices:
#   sudo tests/vm/make-disk.sh [image] [output-dir]
#
# The image must be in rootful podman storage. Either build it with sudo
# podman, or copy it across:
#   podman save localhost/dux-atomic:dev | sudo podman load

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
image=${1:-localhost/dux-atomic:dev}
out=${2:-$repo_root/output}
mkdir -p "$out"

if ! podman image exists "$image"; then
  echo "image $image is not in rootful podman storage" >&2
  echo "copy it in with: podman save $image | sudo podman load" >&2
  exit 2
fi

podman run --rm --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$out:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  build "$image" --type qcow2 --rootfs btrfs --use-librepo=True --output /output \
  --chown "${SUDO_UID:-0}:${SUDO_GID:-0}"
