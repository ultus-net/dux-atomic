#!/usr/bin/env bash
# One static gate for CI and `just check`, so local and CI agree.
# Needs podman or docker. The linter versions are pinned here only.
#
#   CONTAINER_RUNTIME=podman tests/lint.sh

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# Tags are for readers; the digest is what runs. Bump both together.
shellcheck_image=${SHELLCHECK_IMAGE:-docker.io/koalaman/shellcheck:v0.10.0@sha256:0fa384f2a6171aef8aab2999a531c8c8158727d54a8f20157a5c3c51a734d6b2}
hadolint_image=${HADOLINT_IMAGE:-docker.io/hadolint/hadolint:v2.12.0@sha256:9259e253a4e299b50c92006149dd3a171c7ea3c5bd36f060022b5d2c1ff0fbbe}
actionlint_image=${ACTIONLINT_IMAGE:-docker.io/rhysd/actionlint:1.7.7@sha256:1d74bfc9fd1963af8f89a7c22afaaafd42f49aad711a09951d02cb996398f61d}

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
  build/install-packages.sh
  build/package-lock.sh
  tests/lint.sh
  tests/test-signing.sh
  tests/test-static.sh
  tests/verify-image.sh
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

"$runtime" run --rm -v "$repo_root:/mnt:ro" -w /mnt "$actionlint_image" \
  .github/workflows/ci.yml

bash tests/test-static.sh
