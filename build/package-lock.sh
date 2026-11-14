#!/usr/bin/env bash
# Print the installed NEVRA and origin repository of every package that was
# installed from a non-Fedora origin repository in the built image.
#
#   build/package-lock.sh [image]
#
# Contract: one line per resolved NEVRA: <nevra> TAB <from_repo>.
# Packages whose from_repo is empty, '@System', 'unknown', or a local path
# (begins with '/') are excluded. Fedora-origin repositories are excluded so a
# Fedora updates bump does not red the gate. +git builds are excluded.

set -euo pipefail

image=${1:-localhost/dux-atomic:dev}
runtime=${CONTAINER_RUNTIME:-podman}

cat <<'HEADER'
# manifests/packages-common.lock - regenerate with 'just lock'
# One line per resolved NEVRA: <nevra> TAB <from_repo>.
# Records every package whose origin repository is not a Fedora repository.
# COPR publishes a main repository and a dependency repository; which one
# served a package can vary at build time, so the generator normalizes the
# dependency-repo prefix to the main project prefix before recording. The
# NEVRA still pins what landed, and a package moving between those two
# repositories of the same COPR is therefore not drift.
HEADER

# Run repoquery once inside the image. Pass an explicit '*' pattern so every
# installed package is enumerated rather than only the user-installed set.
"$runtime" run --rm "$image" \
  dnf5 repoquery --installed --qf '%{full_nevra}\t%{from_repo}\n' '*' | \
  # Normalize any literal "\\t" sequences into real tabs so the split below
  # works regardless of how repoquery formats its qf output in this rootfs.
  sed 's/\\t/\t/g' | \
  # Normalize COPR repository ids: copr publishes a main repo and a
  # dependency repo. Which repository served a package can vary by build-time
  # resolution but refers to the same COPR project; record the project by
  # normalizing coprdep: to copr: so identical NEVRAs do not appear as drift.
  sed 's/^\([^\t]*\t\)coprdep:/\1copr:/' | \
  LC_ALL=C sort -u | \
  # Denylist Fedora-owned or system origins only. Record everything else so an
  # unexpected repo id is visible rather than dropped. Exclude exactly:
  # fedora, updates, fedora-cisco-openh264, empty, <unknown>, @System, and
  # local paths beginning with '/'. <unknown> is the value dnf5 reports for
  # packages originating from the pinned base image and therefore cannot drift
  # inside that digest.
  awk -F"\t" 'tolower($2) == "" { next } tolower($2) == "<unknown>" { next } tolower($2) == "@system" { next } tolower($2) == "unknown" { next } tolower($2) == "fedora" { next } tolower($2) == "updates" { next } tolower($2) == "fedora-cisco-openh264" { next } $2 ~ /^\// { next } { print }' | \
  # Drop +git NEVRAs (cannot be pinned)
  awk '!index($0, "+git")'
