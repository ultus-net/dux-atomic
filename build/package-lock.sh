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
#
# Scope: manifest names only. Packages those names pull in transitively from a
# third-party repo are not locked; docs/known-gaps.md records that gap. A +git
# build is excluded because it tracks an upstream branch and cannot be pinned.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image=${1:-localhost/dux-atomic:dev}
runtime=${CONTAINER_RUNTIME:-podman}
manifest=$repo_root/manifests/packages-common.txt

# grep exits 1 for an all-comment manifest, which is not an error. Any other
# non-zero exit is a read failure and must stop the run.
if packages=$(grep -Ev '^[[:space:]]*(#.*)?$' "$manifest"); then
  :
else
  status=$?
  if ((status != 1)); then
    echo "cannot read ${manifest} (grep exit ${status})" >&2
    exit 1
  fi
  packages=
fi
if [[ -z $packages ]]; then
  echo "no packages in $manifest" >&2
  exit 1
fi
mapfile -t names <<<"$packages"

cat <<'HEADER'
# manifests/packages-common.lock - regenerate with 'just lock'
# One line per resolved NEVRA: <nevra> TAB <vendor>.
# tests/verify-image.sh compares the non-Fedora lines, because Fedora
# packages move with the updates repository on every build.
# A +git build tracks an upstream branch, so it cannot be pinned and is
# left out of this file and the comparison; the VM boot test covers it.
HEADER

"$runtime" run --rm "$image" bash -c '
  set -euo pipefail
  format="%{NEVRA}\t%{VENDOR}\n"
  for name in "$@"; do
    if out=$(rpm -q --qf "$format" "$name" 2>/dev/null); then
      printf "%s\n" "$out"
    elif providers=$(rpm -q --whatprovides "$name" 2>/dev/null); then
      # Word splitting is intended: rpm prints one provider per line.
      rpm -q --qf "$format" $providers
    else
      echo "no installed package provides ${name}" >&2
      exit 1
    fi
  done
' _ "${names[@]}" | LC_ALL=C sort -u | awk '!index($0, "+git")'
