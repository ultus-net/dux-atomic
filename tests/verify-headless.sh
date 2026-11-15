#!/usr/bin/env bash
# Verify a headless build: the tree with the desktop module removed must still
# build, and the image must carry none of the module's paths or packages.
#
#   tests/verify-headless.sh <image> <packages-desktop.txt>
#
# The package names come from a copy of the manifest the caller saved before
# deleting it, so nothing here names a desktop product.

set -euo pipefail

[[ $# -eq 2 ]] || { echo "Usage: ${BASH_SOURCE[0]} <image> <packages-desktop.txt>" >&2; exit 2; }
image=$1
manifest=$2
runtime=${CONTAINER_RUNTIME:-podman}

[[ -s $manifest ]] || { echo "FAIL the desktop manifest is empty or missing: $manifest" >&2; exit 1; }

"$runtime" run --rm "$image" bootc container lint

# Both paths belong to a module and never to the shared overlay, so a headless
# image that carries either one installed a desktop it was built without.
for path in /usr/libexec/dux-atomic /usr/share/dux-atomic; do
  if "$runtime" run --rm "$image" test -e "$path"; then
    echo "FAIL the headless image carries ${path}, which only a module ships" >&2
    exit 1
  fi
done
echo "ok   the headless image carries no module path"

mapfile -t names < <(grep -Ev '^[[:space:]]*(#.*)?$' "$manifest")
((${#names[@]} > 0)) || { echo "FAIL $manifest names no packages" >&2; exit 1; }

# rpm -q names every missing package and exits 1, so a zero exit means at least
# one name from the desktop set is installed.
if output=$("$runtime" run --rm "$image" rpm -q "${names[@]}" 2>&1); then
  echo "FAIL the headless image installs a name from the desktop manifest:"$'\n'"$output" >&2
  exit 1
fi
echo "ok   none of the ${#names[@]} names in the desktop manifest is installed"
