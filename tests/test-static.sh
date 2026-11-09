#!/usr/bin/env bash
# tests/test-static.sh — cheap sanity checks for the image definition.
# Not a gate on the base image: the tag is intentionally floating while we
# prototype.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

if [[ ! -f $repo_root/Containerfile ]]; then
  echo "FAIL Containerfile is missing" >&2
  failures=$((failures + 1))
elif ! grep -qx 'FROM ${BASE_IMAGE}' "$repo_root/Containerfile"; then
  echo "FAIL Containerfile does not build FROM \${BASE_IMAGE}" >&2
  failures=$((failures + 1))
else
  base=$(sed -n 's/^ARG BASE_IMAGE=//p' "$repo_root/Containerfile" | head -n 1)
  echo "ok   Containerfile builds FROM \${BASE_IMAGE} (${base:-unset})"
fi

manifest=$repo_root/manifests/packages-common.txt
if [[ ! -f $manifest ]]; then
  echo "FAIL manifests/packages-common.txt is missing" >&2
  failures=$((failures + 1))
else
  bad_lines=$(grep -nEv '^[[:space:]]*(#.*)?$|^[A-Za-z0-9][A-Za-z0-9+._-]*$' "$manifest" || true)
  if [[ -n $bad_lines ]]; then
    echo "FAIL packages-common.txt has non-package lines:"$'\n'"$bad_lines" >&2
    failures=$((failures + 1))
  else
    echo "ok   packages-common.txt is one package per line"
  fi
fi

if ((failures > 0)); then
  exit 1
fi
echo "static checks passed"
