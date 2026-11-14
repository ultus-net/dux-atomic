#!/usr/bin/env bash
# build/check-nvidia-modules.sh — fail unless the image build produced every
# NVIDIA module for one kernel. A missing module means the variant boots
# without a driver, and akmods.service cannot build one at first boot.
#
#   build/check-nvidia-modules.sh <kernel-nvr> [modules-root]

set -euo pipefail

if (($# < 1 || $# > 2)); then
  echo "usage: check-nvidia-modules.sh <kernel-nvr> [modules-root]" >&2
  exit 2
fi

kernel=$1
root=${2:-/lib/modules}
dir=$root/$kernel/extra/nvidia
missing=()
for module in nvidia nvidia-uvm nvidia-drm nvidia-modeset nvidia-peermem; do
  # akmods compresses its output, so match the suffix rather than a bare .ko.
  matches=("$dir/$module".ko*)
  if [[ ! -s ${matches[0]} ]]; then
    missing+=("$module")
  fi
done

if ((${#missing[@]} > 0)); then
  echo "the NVIDIA module set is incomplete for kernel ${kernel} under ${dir}: ${missing[*]}" >&2
  exit 1
fi
