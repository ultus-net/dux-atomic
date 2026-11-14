#!/usr/bin/env bash
# build/check-manifest-name.sh — accept a manifest file name, refuse a path.
# build/common.sh prefixes the value with /ctx/manifests/, so a slash is either
# a typo for "packages-nvidia.txt" or an attempt to read another build file.
#
#   build/check-manifest-name.sh packages-nvidia.txt

set -euo pipefail

if (($# == 0)); then
  echo "usage: check-manifest-name.sh <manifest-name>" >&2
  exit 2
fi

name=$1
if [[ -z $name || $name == */* ]]; then
  echo "PACKAGE_MANIFEST_EXTRA must be a file name in manifests/: ${name}" >&2
  exit 1
fi

printf '/ctx/manifests/%s\n' "$name"
