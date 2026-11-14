#!/usr/bin/env bash
# Exercise the package-lock drift comparison without a built image.
# build/compare-lock.sh is the code tests/verify-image.sh runs against the image.

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
compare=$repo_root/build/compare-lock.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# Copied verbatim from manifests/packages-common.lock lines 62, 63 and 70:
# mesa-vulkan-drivers-1:26.2.6-1.fc45.x86_64 is a manifest name, steam is
# another, and steam pulls the 32-bit mesa stack in transitively (see
# tests/verify-image.sh:50-53), so the i686 line is the transitive case. The
# real recorded version is 1:26.2.6-1.fc45.
recorded=$work/recorded.lock
cat >"$recorded" <<'LOCK'
mesa-vulkan-drivers-1:26.2.6-1.fc45.i686	fedora-multimedia
mesa-vulkan-drivers-1:26.2.6-1.fc45.x86_64	fedora-multimedia
steam-0:1.0.0.87-4.fc45.x86_64	fedora-multimedia
LOCK

status=0
"$compare" "$recorded" "$recorded" >"$work/out" 2>"$work/err" || status=$?
if ((status != 0)); then
  echo "FAIL identical inputs exited ${status}, expected 0" >&2
  failures=$((failures + 1))
elif [[ -s $work/out || -s $work/err ]]; then
  echo "FAIL identical inputs printed output" >&2
  failures=$((failures + 1))
else
  echo "ok   identical inputs match and print nothing"
fi

# Case 2 bumps the transitive i686 NEVRA's real release from 1 to 2.
drifted=$work/drifted.lock
cat >"$drifted" <<'LOCK'
mesa-vulkan-drivers-1:26.2.6-1.fc45.x86_64	fedora-multimedia
mesa-vulkan-drivers-1:26.2.6-2.fc45.i686	fedora-multimedia
steam-0:1.0.0.87-4.fc45.x86_64	fedora-multimedia
LOCK
status=0
"$compare" "$recorded" "$drifted" >"$work/out" 2>"$work/err" || status=$?
if ((status != 1)); then
  echo "FAIL a moved transitive NEVRA exited ${status}, expected 1" >&2
  failures=$((failures + 1))
elif ! grep -qF -- '-mesa-vulkan-drivers-1:26.2.6-1.fc45.i686' "$work/err" ||
     ! grep -qF -- '+mesa-vulkan-drivers-1:26.2.6-2.fc45.i686' "$work/err"; then
  echo "FAIL drift did not name the removed and added lines" >&2
  failures=$((failures + 1))
else
  echo "ok   a moved transitive NEVRA drifts and names both lines"
fi

# Case 3 adds a +git NEVRA to the measurement. The helper drops it the way
# build/package-lock.sh drops it, so an extra +git line must not count as drift.
# This line is reconstructed rather than copied: manifests/packages-common.lock
# no longer carries it, so the name and the git snapshot come from
# docs/research/2026-11-10-hyprland-session-assessment.md (dux-greeter-git-2.1.3)
# and CHANGELOG.md's +git entry (git132.7bdf4546).
git_extra=$work/git-extra.lock
cat >"$git_extra" <<'LOCK'
dux-greeter-git-2:2.1.3+git132.7bdf4546-2.fc45.x86_64	copr:copr.fedorainfracloud.org:duxlabs:dux-repo
mesa-vulkan-drivers-1:26.2.6-1.fc45.i686	fedora-multimedia
mesa-vulkan-drivers-1:26.2.6-1.fc45.x86_64	fedora-multimedia
steam-0:1.0.0.87-4.fc45.x86_64	fedora-multimedia
LOCK
status=0
"$compare" "$recorded" "$git_extra" >"$work/out" 2>"$work/err" || status=$?
if ((status != 0)); then
  echo "FAIL a measurement +git line exited ${status}, expected 0" >&2
  failures=$((failures + 1))
else
  echo "ok   a +git line in the measurement alone is not drift"
fi

: >"$work/empty.lock"
status=0
"$compare" "$recorded" "$work/empty.lock" >"$work/out" 2>"$work/err" || status=$?
if ((status != 2)); then
  echo "FAIL an empty measurement exited ${status}, expected 2 (not drift)" >&2
  failures=$((failures + 1))
else
  echo "ok   an empty measurement exits 2, not the drift code"
fi

status=0
"$compare" "$recorded" "$work/absent.lock" >"$work/out" 2>"$work/err" || status=$?
if ((status != 2)); then
  echo "FAIL an unreadable measurement exited ${status}, expected 2 (not drift)" >&2
  failures=$((failures + 1))
else
  echo "ok   an unreadable measurement exits 2, not the drift code"
fi

if ((failures > 0)); then
  exit 1
fi
