#!/usr/bin/env bash
# One static gate for CI and `just check`, so local and CI agree.
# Needs podman or docker. Both linter versions are pinned here only.
#
#   CONTAINER_RUNTIME=podman tests/lint.sh

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shellcheck_image=${SHELLCHECK_IMAGE:-docker.io/koalaman/shellcheck:v0.10.0}
hadolint_image=${HADOLINT_IMAGE:-docker.io/hadolint/hadolint:v2.12.0}

runtime=${CONTAINER_RUNTIME:-}
if [[ -z $runtime ]]; then
  for candidate in podman docker; do
    if command -v "$candidate" >/dev/null 2>&1; then
      runtime=$candidate
      break
    fi
  done
fi
if [[ -z $runtime ]]; then
  echo "need podman or docker to run the pinned linters" >&2
  exit 2
fi

bash_scripts=(
  build/common.sh
  tests/lint.sh
  tests/test-static.sh
  tests/vm/boot-smoke.sh
  tests/vm/make-disk.sh
)
posix_scripts=(
  overlay/usr/libexec/dux-atomic/needs-setup.sh
)

cd "$repo_root"
for script in "${bash_scripts[@]}"; do
  bash -n "$script"
done
for script in "${posix_scripts[@]}"; do
  sh -n "$script"
done

"$runtime" run --rm -v "$repo_root:/mnt:ro" -w /mnt "$shellcheck_image" \
  --severity=warning "${bash_scripts[@]}" "${posix_scripts[@]}"

"$runtime" run --rm -v "$repo_root:/mnt:ro" -w /mnt "$hadolint_image" \
  hadolint --failure-threshold warning Containerfile

bash tests/test-static.sh
