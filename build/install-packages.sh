#!/bin/bash
# Install runner packages, retrying a transient apt failure.
#
# A DNS or mirror blip on a hosted runner must not red a release: run
# 43033654470 spent 67 minutes in the package install before apt reported
# "Temporary failure resolving", and publish, verify and promote never ran.
# Retry at most three times, cap each attempt, and let apt retry each fetch.
#
#   build/install-packages.sh podman skopeo

set -euo pipefail

if (($# == 0)); then
  echo "usage: $0 <package>..." >&2
  exit 2
fi

apt_retry() {
  local attempt
  for attempt in 1 2 3; do
    if timeout 600 sudo env DEBIAN_FRONTEND=noninteractive \
      apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=30 \
      -o Acquire::https::Timeout=30 "$@"; then
      return 0
    fi
    echo "apt-get $* failed on attempt ${attempt} of 3; retrying in 15s" >&2
    sleep 15
  done
  return 1
}

apt_retry update
apt_retry install -y "$@"
