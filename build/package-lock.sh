#!/usr/bin/env bash
# Print the installed NEVRA and vendor of every package the manifest names.
#
#   build/package-lock.sh [image]
#
# The image's rpm database is the source of truth, so the lock records what a
# build actually installed rather than what a repository offers. A manifest
# entry may name a provides rather than a package (xinit, dms-greeter), so a
# failed exact query falls back to the providing package. Regenerate the lock
# with `just lock`.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image=${1:-localhost/dux-atomic:dev}
runtime=${CONTAINER_RUNTIME:-podman}
manifest=$repo_root/manifests/packages-common.txt

mapfile -t packages < <(grep -Ev '^[[:space:]]*(#.*)?$' "$manifest")
if ((${#packages[@]} == 0)); then
  echo "no packages in $manifest" >&2
  exit 1
fi

cat <<'HEADER'
# manifests/packages-common.lock - regenerate with 'just lock'
# One line per resolved package: <nevra> TAB <vendor>. tests/verify-image.sh
# compares the non-Fedora lines, because Fedora packages move with the updates
# repository on every build.
HEADER

"$runtime" run --rm "$image" bash -c '
  set -euo pipefail
  format="%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\t%{VENDOR}\n"
  for name in "$@"; do
    if out=$(rpm -q --qf "$format" "$name" 2>/dev/null); then
      printf "%s\n" "$out"
    elif providers=$(rpm -q --whatprovides "$name" 2>/dev/null); then
      rpm -q --qf "$format" $providers
    else
      echo "no installed package provides ${name}" >&2
      exit 1
    fi
  done
' _ "${packages[@]}" | sort -u
