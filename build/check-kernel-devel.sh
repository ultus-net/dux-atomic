#!/usr/bin/env bash
# build/check-kernel-devel.sh — fail when no installed kernel-devel matches the
# newest installed kernel. akmods builds against the running kernel's headers,
# so a devel for another kernel is a first-boot failure, not a build failure.
#
#   build/check-kernel-devel.sh <newest-kernel-nvr> <devel-nvr>...

set -euo pipefail

if (($# == 0)); then
  echo "usage: check-kernel-devel.sh <newest-kernel-nvr> <devel-nvr>..." >&2
  exit 2
fi

kernel=$1
shift
for devel in "$@"; do
  if [[ $devel == "$kernel" ]]; then
    exit 0
  fi
done

echo "kernel-devel does not match the newest kernel ${kernel}" >&2
exit 1
