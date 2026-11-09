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

image=${1:-localhost/dux-atomic:dev}
out=${2:-output}
mkdir -p "$out"

podman run --rm --privileged --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$(pwd)/$out:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  build "$image" --type qcow2 --rootfs btrfs --use-librepo=True --output /output
