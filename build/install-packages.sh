#!/bin/bash
# Install runner packages, retrying a transient apt failure.
#
# A DNS or mirror blip on a hosted runner must not red a release: run
# 43033654470 spent 67 minutes in the package install before apt reported
# "Temporary failure resolving", and publish, verify and promote never ran.
# Retry at most three times, cap each attempt, and let apt retry each fetch.
# The whole install shares one budget, so the worst case fits the tightest
# calling job bound, which is promote's ten minutes.
#
#   build/install-packages.sh podman skopeo

set -euo pipefail

if (($# == 0)); then
  echo "usage: $0 <package>..." >&2
  exit 2
fi

budget=300
deadline=$((SECONDS + budget))

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
      apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=30 \
      -o Acquire::https::Timeout=30 "$@"; then
      return 0
    fi
    echo "apt-get $* failed on attempt ${attempt} of 3" >&2
    ((attempt < 3)) || return 1
    sleep 15
  done
  return 1
}

apt_retry update
apt_retry install -y "$@"
