#!/usr/bin/env bash
# The apt mirror failover keys on an entry's position, never on its hostname.
#
# Run 44300517908 lost two image jobs: the runner's mirror list named
# us-east-2.ec2.archive.ubuntu.com, the helper matched only
# azure.archive.ubuntu.com, so nothing was ever commented out and every apt
# attempt retried the same slow mirror until the budget ran out (#143).
#
#   tests/test-apt-mirror.sh

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../build/apt-mirror.sh
. "$repo_root/build/apt-mirror.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The helper writes the list through sudo, which a hosted runner has and a
# developer box may not, so the test supplies a pass-through sudo and exercises
# the real function either way.
mkdir -p "$work/bin"
printf '#!/bin/sh\nexec "$@"\n' >"$work/bin/sudo"
chmod +x "$work/bin/sudo"
PATH=$work/bin:$PATH

failures=0
fail() { echo "FAIL $*" >&2; failures=$((failures + 1)); }
pass() { echo "ok   $*"; }

# Whatever the first entry's host, it is the one apt retries, so it is the one
# that must be commented out. The second entry must survive untouched.
failover_by_position() {
  local label=$1 first=$2 second=$3 file out
  file=$work/$label.txt
  printf '%s\n%s\n' "$first" "$second" >"$file"
  if ! out=$(deprioritise_primary_mirror "$file"); then
    fail "the $label list was not failed over"
    return
  fi
  [[ $out == "$first" ]] || fail "the $label list reported '$out' instead of '$first'"
  [[ $(sed -n 1p "$file") == "# $first" ]] || fail "the $label list left its first entry active"
  [[ $(sed -n 2p "$file") == "$second" ]] || fail "the $label list changed its second entry"
  pass "a list whose first entry is the $label mirror fails over by position"
}

failover_by_position azure \
  http://azure.archive.ubuntu.com/ubuntu/ http://archive.ubuntu.com/ubuntu/
failover_by_position regional \
  http://us-east-2.ec2.archive.ubuntu.com/ubuntu/ http://archive.ubuntu.com/ubuntu/

# A list with nothing left to fail over to must be left as it is, never
# emptied, because an empty list breaks every later apt call too.
unchanged() {
  local label=$1 file=$2 before
  before=$(cat "$file")
  if deprioritise_primary_mirror "$file" >/dev/null; then
    fail "the $label list was changed when it had nothing to fail over to"
  elif [[ $(cat "$file") != "$before" ]]; then
    fail "the $label list was modified by a call that reported no change"
  else
    pass "a $label list is left unchanged"
  fi
}

printf 'http://archive.ubuntu.com/ubuntu/\n' >"$work/single.txt"
unchanged single-entry "$work/single.txt"

printf '# http://azure.archive.ubuntu.com/ubuntu/\n# http://archive.ubuntu.com/ubuntu/\n' \
  >"$work/commented.txt"
unchanged fully-commented "$work/commented.txt"

if deprioritise_primary_mirror "$work/missing.txt" >/dev/null; then
  fail "a missing mirror list was reported as changed"
else
  pass "a missing mirror list is reported as nothing to change"
fi

# Each call drops one entry, so three entries survive two failures plus one.
file=$work/three.txt
printf '%s\n%s\n%s\n' \
  http://us-east-2.ec2.archive.ubuntu.com/ubuntu/ \
  http://archive.ubuntu.com/ubuntu/ \
  http://security.ubuntu.com/ubuntu/ >"$file"
deprioritise_primary_mirror "$file" >/dev/null
deprioritise_primary_mirror "$file" >/dev/null
if [[ $(grep -cE '^[[:space:]]*https?://' "$file") == 1 ]] &&
  grep -qF 'http://security.ubuntu.com/ubuntu/' "$file"; then
  pass "two failures leave one mirror active"
else
  fail "two failures did not leave exactly the last mirror active"
fi

((failures == 0)) || {
  echo "apt mirror failover: $failures failure(s)" >&2
  exit 1
}
echo "apt mirror failover checks passed"
