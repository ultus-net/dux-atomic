#!/bin/bash
# Install runner packages, retrying a transient apt failure and failing over
# off a dead mirror.
#
# A DNS or mirror blip on a hosted runner must not red a release. Run
# 43033654470 spent 67 minutes in the package install before apt reported
# "Temporary failure resolving", and publish, verify and promote never ran. Run
# 43052107613 then burned the whole budget on `Ign:` lines for
# azure.archive.ubuntu.com without ever reaching the next mirror.
#
# The runner image points every suite at mirror+file:/etc/apt/apt-mirrors.txt,
# and its first entry is the mirror apt tries first. apt spends every
# Acquire::Retries attempt on the same URI before it re-ranks the list, so a
# higher count delays the failover instead of adding resilience. Keep one
# attempt, drop the delay (apt 2.8 hangs on a dead first mirror without it), and
# comment that first entry out between attempts so the next one goes straight to
# the rest of the list.
#
# The entry is chosen by position, not by hostname. Run 44300517908 lost two
# image jobs because the list named us-east-2.ec2.archive.ubuntu.com while this
# script matched only azure.archive.ubuntu.com, so nothing was ever commented
# out and every attempt retried the same slow mirror (#143).
#
# https://github.com/actions/runner-images/issues/14823
#
#   build/install-packages.sh podman skopeo

set -euo pipefail

if (($# == 0)); then
  echo "usage: $0 <package>..." >&2
  exit 2
fi

mirrors=${APT_MIRRORS_FILE:-/etc/apt/apt-mirrors.txt}
budget=300
deadline=$((SECONDS + budget))

helper_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=apt-mirror.sh
. "$helper_dir/apt-mirror.sh"

apt_retry() {
  local attempt cap
  for attempt in 1 2 3; do
    cap=$((deadline - SECONDS))
    if ((cap <= 0)); then
      echo "install budget of ${budget}s is spent" >&2
      return 1
    fi
    ((cap > 180)) && cap=180
    if timeout "$cap" sudo env DEBIAN_FRONTEND=noninteractive \
      apt-get -o Acquire::Retries=1 -o Acquire::Retries::Delay=false \
      -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15 "$@"; then
      return 0
    fi
    echo "apt-get $* failed on attempt ${attempt} of 3" >&2
    ((attempt < 3)) || return 1
    if dropped=$(deprioritise_primary_mirror "$mirrors"); then
      echo "commented out the primary mirror ($dropped); the next attempt uses the rest" >&2
    fi
    sleep 15
  done
  return 1
}

apt_retry update
apt_retry install -y "$@"
