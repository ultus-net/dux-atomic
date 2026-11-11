#!/usr/bin/env bash
# tests/test-signing.sh — prove a containers signature policy accepts a signed
# image and rejects an unsigned or wrong-key one.
#
# Needs podman, skopeo, curl and cosign on PATH, and a free 127.0.0.1:5000. The
# script runs its own throwaway registry, pulls digest-pinned images, and keeps
# the fixture keys, policy and registries.d file in a temp dir removed on exit.
# It never contacts GitHub or any signing service, so it runs offline from CI's
# identity and needs no OIDC token.
#
# cosign must be v2, the version CI pins. v3 signs with a bundle format that
# containers/image cannot read (container-libs#388).
#
#   tests/test-signing.sh

set -euo pipefail

for tool in cosign curl podman skopeo; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "need $tool on PATH to run the signing tests" >&2
    exit 2
  fi
done

cosign_version=$(cosign version 2>/dev/null | sed -n 's/^GitVersion:[[:space:]]*//p')
if [[ ${cosign_version#v} != 2.* ]]; then
  echo "need cosign v2, the version CI pins, got ${cosign_version:-unknown}:" >&2
  echo "v3 signs with a bundle format containers/image cannot read (container-libs#388)" >&2
  exit 2
fi

# Tags are for readers; the digest is what runs. Bump both together.
registry_image=${REGISTRY_IMAGE:-docker.io/library/registry:2@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373}
payload_image=${PAYLOAD_IMAGE:-docker.io/library/hello-world:latest@sha256:c567b231f65614688711a75f31518a064258a51d442117a3e771a3a8fdba78ef}

# REGISTRY_PORT lets a host that already owns 5000 run the suite elsewhere.
registry_port=${REGISTRY_PORT:-5000}
repo=127.0.0.1:${registry_port}/dux-atomic-signing
registry_name=dux-atomic-signing-registry
tmp=$(mktemp -d "${TMPDIR:-/tmp}/dux-atomic-signing.XXXXXX")

cleanup() {
  podman rm -f "$registry_name" >/dev/null 2>&1 || true
  podman rmi -f "$repo:signed" "$repo:unsigned" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

podman run -d --rm --name "$registry_name" -p "127.0.0.1:${registry_port}:5000" "$registry_image" >/dev/null

ready=
for _ in {1..60}; do
  if curl -fsS "http://127.0.0.1:${registry_port}/v2/" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ -z $ready ]]; then
  echo "the local registry never answered on 127.0.0.1:${registry_port}" >&2
  exit 1
fi

# The two tags must carry different digests. A signature is attached to the
# digest, so a second tag on the same digest would inherit the signature and
# could never exercise rejection. registry:2 is already pulled to run the
# registry, so it costs no extra download.
podman pull "$payload_image" >/dev/null
podman pull "$registry_image" >/dev/null
podman tag "$payload_image" "$repo:signed"
podman tag "$registry_image" "$repo:unsigned"
podman push --tls-verify=false --digestfile "$tmp/signed.digest" "$repo:signed" >/dev/null
podman push --tls-verify=false "$repo:unsigned" >/dev/null
signed_digest=$(<"$tmp/signed.digest")

mkdir -p "$tmp/trusted" "$tmp/untrusted"
# An empty COSIGN_PASSWORD keeps cosign from prompting for one.
(cd "$tmp/trusted" && COSIGN_PASSWORD='' cosign generate-key-pair >/dev/null)
(cd "$tmp/untrusted" && COSIGN_PASSWORD='' cosign generate-key-pair >/dev/null)

# --tlog-upload=false keeps the run offline. containers/image requires a Rekor
# entry only when the policy names a Rekor key, and this fixture names none.
COSIGN_PASSWORD='' cosign sign --yes --key "$tmp/trusted/cosign.key" \
  --tlog-upload=false --allow-insecure-registry "$repo:signed" >/dev/null

# cosign writes the repository, not the tag, into the signature payload, so an
# exact tag match would reject a valid signature. matchRepository is the match
# that a cosign-signed image can satisfy for both a tag and a digest reference.
cat >"$tmp/policy.json" <<JSON
{
  "default": [
    {
      "type": "reject"
    }
  ],
  "transports": {
    "docker": {
      "$repo": [
        {
          "type": "sigstoreSigned",
          "keyPath": "$tmp/trusted/cosign.pub",
          "signedIdentity": {
            "type": "matchRepository"
          }
        }
      ]
    }
  }
}
JSON

# Without use-sigstore-attachments, containers/image looks in a local lookaside
# directory instead of the registry and reports that no signature exists, so
# every case would reject for the wrong reason.
mkdir -p "$tmp/registries.d"
cat >"$tmp/registries.d/local.yaml" <<YAML
docker:
  127.0.0.1:${registry_port}:
    use-sigstore-attachments: true
YAML

failures=0
cases=0
case_log=$tmp/case.log
# skopeo 1.13.3, the version Ubuntu 24.04 installs, stats the dir: destination
# while parsing the reference, so its parent must exist before the first copy.
mkdir -p "$tmp/out"

check() {
  local expected=$1 label=$2 reference=$3 destination=$4 reason=${5:-}
  local got
  cases=$((cases + 1))
  if skopeo --policy "$tmp/policy.json" --registries.d "$tmp/registries.d" \
      copy --src-tls-verify=false "docker://$reference" "dir:$destination" \
      >"$case_log" 2>&1; then
    got=accept
  else
    got=reject
  fi
  if [[ $got != "$expected" ]]; then
    printf 'FAIL %s: expected %s, got %s\n' "$label" "$expected" "$got" >&2
    tail -n 20 "$case_log" >&2
    failures=$((failures + 1))
  elif [[ -n $reason ]] && ! grep -q -- "$reason" "$case_log"; then
    printf 'FAIL %s: rejected without the expected policy error (%s)\n' "$label" "$reason" >&2
    tail -n 20 "$case_log" >&2
    failures=$((failures + 1))
  else
    printf 'ok   %s: %s\n' "$label" "$got"
  fi
}

check accept "signed tag" "$repo:signed" "$tmp/out/signed-tag"
check accept "signed digest" "$repo@$signed_digest" "$tmp/out/signed-digest"
check reject "unsigned tag" "$repo:unsigned" "$tmp/out/unsigned-tag" \
  "A signature was required, but no signature exists"

# A signature from a key the policy does not trust must not pass either.
COSIGN_PASSWORD='' cosign sign --yes --key "$tmp/untrusted/cosign.key" \
  --tlog-upload=false --allow-insecure-registry "$repo:unsigned" >/dev/null
check reject "wrong-key signature" "$repo:unsigned" "$tmp/out/wrong-key" \
  "cryptographic signature verification failed"

if ((failures > 0)); then
  echo "$failures of $cases signing cases failed" >&2
  exit 1
fi
echo "all $cases signing cases behaved as expected"
