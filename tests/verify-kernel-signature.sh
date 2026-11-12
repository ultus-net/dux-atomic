#!/usr/bin/env bash
# Fail unless the running image's kernel is signed by Fedora.
#
# Runs inside the image with the repository mounted at /opt, which is a real
# directory there. Do not use /mnt: it is a symlink in this base, and an older
# crun cannot create a bind mount over it (run 43174150389 failed that way).
# Secure Boot needs no per-machine enrollment only while the base keeps Fedora's
# signed kernel, and a base bump can change that silently, so the image job
# checks it (#65). The old Universal Blue base also shipped a signed kernel,
# signed by CN=ublue kernel, so the issuer is what tells the two chains apart.

set -euo pipefail

set -- /usr/lib/modules/*/vmlinuz
if (( $# != 1 )); then
  echo "FAIL expected one kernel under /usr/lib/modules, found $#" >&2
  exit 1
fi

signature=$(mktemp)
certificates=$(mktemp)
trap 'rm -f "$signature" "$certificates"' EXIT

python3 /opt/tests/pe-signature.py "$1" >"$signature"
openssl pkcs7 -inform DER -in "$signature" -print_certs -noout >"$certificates"
cat "$certificates"

# Fedora's kernel carries exactly one certificate. A bag with more could hold
# Fedora's certificate beside another signer's and pass the name checks below,
# so require the single-certificate shape first.
signers=$(grep -c '^subject=' "$certificates" || true)
if (( signers != 1 )); then
  echo "FAIL expected exactly one certificate in the kernel signature, found $signers" >&2
  exit 1
fi
if ! grep -q 'CN=fedoraca' "$certificates"; then
  echo "FAIL the kernel signature was not issued by CN=fedoraca" >&2
  exit 1
fi
if ! grep -q 'CN=kernel-signer' "$certificates"; then
  echo "FAIL the kernel signature does not name CN=kernel-signer as its subject" >&2
  exit 1
fi
