#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/build/agent-container.sh"

# Create isolated scratch per-run; TMPDIR may be set externally.
tmp_proj=$(mktemp -d "${TMPDIR:-/tmp}/opencode-agent-demo.XXXX")
trap 'rm -rf "${tmp_proj}"' EXIT
printf 'hello\n' > "$tmp_proj/file.txt"

export AGENT_CONTAINER_DRY_RUN=1

# Clean dry run should succeed
if ! output=$("$script" localhost/dux-atomic:dev "$tmp_proj" -- /bin/true 2>&1); then
  echo "FAIL: clean dry run failed" >&2
  echo "$output" >&2
  exit 1
fi

echo "$output" | grep -q "DRY RUN" || (echo "FAIL: dry run output missing" >&2; exit 1)
# The project must be the source of a /work mount, not mounted at its host path.
echo "$output" | grep -qF "$tmp_proj:/work:Z" \
  || (echo "FAIL: project is not mounted at /work: $output" >&2; exit 1)
echo "$output" | grep -qF " -w /work " \
  || (echo "FAIL: the workdir is not /work: $output" >&2; exit 1)
if echo "$output" | grep -qF "$tmp_proj:$tmp_proj"; then
  echo "FAIL: project is also mounted at its host path: $output" >&2
  exit 1
fi

# Red cases: tokens that must be rejected (various spellings)
red_cases=(
  "--volume /home:/host"
  "--volume=/home:/host"
  "-v /:/host"
  "-v/home:/host"
  "--mount type=bind,source=/home,destination=/host"
  "--mount=type=bind,source=/home,destination=/host"
  "--privileged=true"
  "--privileged"
  "--network host"
  "--network=host"
  "--pid=host"
  "--device /dev/kvm"
  "--device=/dev/kvm"
  "--cap-add=ALL"
  "--workdir=/etc"
  "-e FOO=bar --volume /home:/host"
  "--name test-agent --privileged"
  "--name a b"
)
for rcases in "${red_cases[@]}"; do
  export AGENT_CONTAINER_EXTRA="$rcases"
  rc=0
  set +e
  out=$("$script" localhost/dux-atomic:dev "$tmp_proj" -- /bin/true 2>&1) || rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "FAIL: script allowed disallowed extra: $rcases" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "$out" | grep -q "ERROR: AGENT_CONTAINER_EXTRA" || (echo "FAIL: unexpected output for $rcases: $out" >&2; exit 1)
  echo "OK: disallowed extra '$rcases' rejected as expected: exit $rc" >&2
done

# Green allowlist cases: these must be accepted
green_cases=(
  "-e FOO=bar"
  "--network=none"
  "--name test-agent"
  "--detach"
  "--workdir /work"
)
for g in "${green_cases[@]}"; do
  export AGENT_CONTAINER_EXTRA="$g"
  rc=0
  set +e
  out=$("$script" localhost/dux-atomic:dev "$tmp_proj" -- /bin/true 2>&1) || rc=$?
  set -e
  if [[ ${rc:-0} -ne 0 ]]; then
    echo "FAIL: allowlist token rejected: $g" >&2
    echo "$out" >&2
    exit 1
  fi
  echo "$out" | grep -q "DRY RUN" || (echo "FAIL: dry run missing for allowlist $g: $out" >&2; exit 1)
  echo "OK: allowlist extra '$g' accepted" >&2
done

# The temporary home must follow TMPDIR. A hardcoded path breaks on any host
# that does not have it, which is how the first version failed in CI.
export AGENT_CONTAINER_EXTRA=
tmp_parent=$tmp_proj/tmpdir
mkdir -p "$tmp_parent"
out=$(TMPDIR=$tmp_parent "$script" localhost/dux-atomic:dev "$tmp_proj" -- /bin/true 2>&1) \
  || (echo "FAIL: dry run under a custom TMPDIR failed: $out" >&2; exit 1)
echo "$out" | grep -qF "$tmp_parent/dux-atomic-agent." \
  || (echo "FAIL: the temporary home ignores TMPDIR: $out" >&2; exit 1)
echo "OK: the temporary home follows TMPDIR" >&2

echo "agent-container tests passed"
