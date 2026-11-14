#!/usr/bin/env bash
# Compare the recorded package lock with a measured package list as sets.
#
#   build/compare-lock.sh <recorded-lock> <measured-list>
#
# Contract: exit 0 and print nothing when the sets match. Exit 1 on drift and
# print the added and removed lines to stderr. Exit 2 when an input is
# unreadable or has no data lines, so a failed measurement never looks like
# drift. The measured list drops +git NEVRAs the same way build/package-lock.sh
# does.

set -euo pipefail

if (( $# != 2 )); then
  echo "usage: build/compare-lock.sh <recorded-lock> <measured-list>" >&2
  exit 2
fi

recorded_path=$1
measured_path=$2

if [[ ! -r $recorded_path || ! -r $measured_path ]]; then
  echo "build/compare-lock.sh: cannot read an input: ${recorded_path} ${measured_path}" >&2
  exit 2
fi

recorded=$(grep -vE '^(#|$)' "$recorded_path" || true)
measured=$(grep -vE '^(#|$)' "$measured_path" || true)
if [[ -z $recorded || -z $measured ]]; then
  echo "build/compare-lock.sh: an input has no data lines: ${recorded_path} ${measured_path}" >&2
  exit 2
fi

measured=$(awk '!index($0, "+git")' <<<"$measured")
recorded=$(LC_ALL=C sort -u <<<"$recorded")
measured=$(LC_ALL=C sort -u <<<"$measured")

if [[ $recorded == "$measured" ]]; then
  exit 0
fi

diff -u <(printf '%s\n' "$recorded") <(printf '%s\n' "$measured") >&2 || true
exit 1
