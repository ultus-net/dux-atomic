#!/usr/bin/env bash
# Verify a headless build: the tree with the desktop module removed must still
# build, keep the shared image behaviour, and carry nothing the module ships.
#
#   tests/verify-headless.sh <image> <packages-desktop.txt> <module-paths.txt>
#
# The caller saves both lists from git before deleting the module, so every name
# and path here comes from the tree and a swapped module is covered unchanged.

set -euo pipefail

[[ $# -eq 3 ]] || { echo "Usage: ${BASH_SOURCE[0]} <image> <packages-desktop.txt> <module-paths.txt>" >&2; exit 2; }
image=$1
manifest=$2
path_list=$3
runtime=${CONTAINER_RUNTIME:-podman}
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

[[ -s $manifest ]] || { echo "FAIL the desktop manifest is empty or missing: $manifest" >&2; exit 1; }
[[ -s $path_list ]] || { echo "FAIL the module path list is empty or missing: $path_list" >&2; exit 1; }

# Removing a module must not change the rest of the image, so run the shared
# assertions from the image verifier. It skips the desktop contract and the
# package lock, both of which describe the set the module installs.
"$repo_root/tests/verify-image.sh" --headless --no-package-lock "$image"
echo "ok   the headless image keeps the shared behaviour the image verifier asserts"

# Every file the module ships must be absent. The list comes from the tree, so
# this covers the units, the presets, the tmpfiles rule and the seeds without
# naming any of them.
mapfile -t paths < <(grep -Ev '^[[:space:]]*(#.*)?$' "$path_list")
((${#paths[@]} > 0)) || { echo "FAIL $path_list names no paths" >&2; exit 1; }
present=$(printf '%s\n' "${paths[@]}" |
  "$runtime" run --rm -i "$image" bash -c 'while read -r path; do if [[ -e $path ]]; then echo "$path"; fi; done')
if [[ -n $present ]]; then
  echo "FAIL the headless image carries files the module ships:"$'\n'"$present" >&2
  exit 1
fi
echo "ok   none of the ${#paths[@]} paths the module ships is in the image"

# rpm -q names every missing package and exits 1, so a zero exit means at least
# one name from the module's set is installed.
mapfile -t names < <(grep -Ev '^[[:space:]]*(#.*)?$' "$manifest")
((${#names[@]} > 0)) || { echo "FAIL $manifest names no packages" >&2; exit 1; }
if output=$("$runtime" run --rm "$image" rpm -q "${names[@]}" 2>&1); then
  echo "FAIL the headless image installs a name from the desktop manifest:"$'\n'"$output" >&2
  exit 1
fi
echo "ok   none of the ${#names[@]} names in the desktop manifest is installed"
