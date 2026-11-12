# :latest promotion 3, commit 8b42a11

`ghcr.io/ultus-net/dux-atomic:latest` moved to the digest of commit `8b42a11`,
the merge of PR #56. This is the first promoted digest built from Fedora's own
bootc base rather than Universal Blue's, and the first whose SBOM attestation is
discoverable in the Sigstore bundle format.

Three merges are inside this build:

| Merge | Change |
| --- | --- |
| `e737c39` (#62) | `cosign attest --new-bundle-format`, so the SPDX attestation is visible to `cosign verify-attestation` |
| `5d64c26` (#60) | Base swap to `quay.io/fedora/fedora-bootc:45`, manifest rewrite, portal override |
| `8b42a11` (#56) | Encryption and Secure Boot decision record, install and known-gap rewrite |

## What moved

| Ref | Digest | Layers |
| --- | --- | --- |
| `:latest` | `sha256:83dfaa21dedba3c621cf1a4e5d2b70e549e65fd8844f3ebf8554a450eb0074e0` | 67 |
| `sha-8b42a1116552dd12d82a9eb6f905f0bde3d7a5b9` | `sha256:83dfaa21dedba3c621cf1a4e5d2b70e549e65fd8844f3ebf8554a450eb0074e0` | 67 |
| `:latest` before this run (`284942b`) | `sha256:3b72522f1e85abb65d4bef055e23bc753189282158b89f24fd4e37d4c13b5593` | 261 |

The layer count fell from 261 to 67 because the base changed, not because
content was dropped: the Universal Blue base layered a desktop and its kernel on
top of Fedora's packages, and `fedora-bootc` starts from the smaller set the
image actually needs. The published image artifact fell from 7,823,295,732 bytes
to 5,237,372,148 bytes for the same reason.

## The run

`workflow_dispatch` with `promote=true` on `main`, run
[43157860388](https://github.com/ultus-net/dux-atomic/actions/runs/43157860388),
at `8b42a11`:

| Job | Result | Time | Window (UTC) |
| --- | --- | --- | --- |
| `static` | success | 19s | 05:06:04 to 05:06:23 |
| `signing` | success | 20s | 05:06:25 to 05:06:45 |
| `image` | success | 19m56s | 05:06:25 to 05:26:21 |
| `publish` | success | 6m41s | 05:26:26 to 05:33:07 |
| `verify` | success | 28s | 05:33:09 to 05:33:37 |
| `promote` | success | 16s | 05:33:41 to 05:33:57 |

The run was created at 04:54:53 and finished at 05:33:58, so 39m05s in total.
`static` did not start until 05:06:04, so 11m11s of that was queue time. The
push run for the same commit, 43157839588, was cancelled by the workflow's
concurrency group when this dispatch started, so this is the only run on
`8b42a11` that published a digest.

Every job here finished faster than its counterpart in promotion 2: `image` took
19m56s against 29m52s, `publish` 6m41s against 13m13s, and the queue wait was
11m11s against 51m49s.

### Where the image job's 19m56s went

| Step | Time |
| --- | --- |
| Free runner disk space | 2m26s |
| Install podman and qemu | 14s |
| Build image | 2m47s |
| Image lint and unit verify | 3s |
| Export image | 39s |
| SBOM | 1m48s |
| Upload SBOM | 1s |
| Build disk | 5m46s |
| Boot smoke test | 4m34s |
| Vulnerability scan | 43s |
| Upload scan report | 1s |
| Upload image artifact | 44s |

The boot smoke test boots the built qcow2 under TCG and waits for a serial login
prompt, so this run proves the Fedora base reaches that prompt in the VM. It is
also the cheapest part of the job now: 4m34s against 6m38s in promotion 2 and
42m53s in run 43068532421, which is why the 1800s `BOOT_TIMEOUT` still bounds the
step rather than any measured figure.

### Where publish's 6m41s went

| Step | Time |
| --- | --- |
| Download image | 4m10s |
| Download SBOM | under 1s |
| Install podman and skopeo | 4s |
| Log in to GHCR | 4s |
| Push the commit tag | 1m45s |
| Record the pushed digest | under 1s |
| Write the publish helpers | under 1s |
| Install cosign | 5s |
| Sign the digest | 13s |
| Attest the SBOM | 5s |
| Attest build provenance | 8s |
| Upload publish logs | 1s |

This is the first promotion whose publish job attests build provenance, so the
digest carries a signature, an SPDX attestation, and a SLSA provenance
attestation. All three steps succeeded on their first attempt.

### Verify and promote

`verify` spent 3s on the signature, 3s on `--type spdxjson`, and 5s on the
provenance check, then uploaded 653,316 bytes of logs.

`promote` installed `skopeo` in 5s, logged in to GHCR in 2s, and moved `:latest`
in 5s. It needs `publish` and `verify`, so the tag moved onto a digest whose
signature and both attestations had already been checked.

Artifact sizes from the run's artifacts API: `image` 5,237,372,148 bytes,
`verify-logs` 653,316, `sbom` 388,019, `publish-logs` 1,406, and
`trivy-report` 763.

## Independent confirmation

Read from the registry, not from the workflow's own log, on 2026-11-12:

- `skopeo inspect docker://ghcr.io/ultus-net/dux-atomic:latest` and the same
  command against `:sha-8b42a1116552dd12d82a9eb6f905f0bde3d7a5b9` both report
  `sha256:83dfaa21…` with 67 layers, so the promoted tag and the commit tag are
  one digest.
- `cosign verify`, pinned to
  `https://github.com/ultus-net/dux-atomic/.github/workflows/ci.yml@refs/heads/main`
  with issuer `https://token.actions.githubusercontent.com`, exits 0. It prints
  that the cosign claims were validated, that existence in the transparency log
  was verified offline, and that the code-signing certificate chained to a
  trusted CA.
- `cosign verify-attestation --type spdxjson` against the same digest exits 0
  and lists two predicates:
  `https://spdx.dev/Document` and `https://slsa.dev/provenance/v1`. That is the
  #62 fix working against the live registry for the first time, and it is why
  the run's `Verify the attestation` step did not fail the way run 43106659542
  did.

## The Secure Boot chain in this digest

Measured on the image built from the base in #59 on 2026-11-12:

- `rpm -q` reports vendor `Fedora Project` for `kernel-core-7.3.3-300.fc45`,
  `shim-x64-16.1`, and `grub2-efi-x64-2.12-83.fc45`.
- `/usr/lib/modules/7.3.3-300.fc45.x86_64/vmlinuz` carries a PE certificate
  table of 1896 bytes. The PKCS#7 inside it is revision `0x200`, type `0x2`,
  subject `CN=kernel-signer, OU=bkernel01 kernel, OU=Fedora Secure Boot Signer,
  O=Red Hat, Inc.`, issuer `CN=fedoraca, OU=Fedora Secure Boot CA 20200709`.
- `modinfo -F signer` reports `Fedora kernel signing key` for
  `nf_tables.ko.xz` and `nouveau.ko.xz`.
- `/etc/pki/akmods/certs/` does not exist, so no Universal Blue kernel key ships.

The decision this supports, and what it still leaves unproven, are in
[Disk encryption and Secure Boot policy](2026-11-12-luks-secureboot-policy.md)
(#54).

## Accepted at promotion

- No bare-metal install exists on either target, and no boot with Secure Boot
  enabled has been recorded on hardware. The signatures above are measured from
  the image. `docs/install.md` carries the order the operator chose for the
  first install: Secure Boot off first, then enable it and boot again.
- The desktop cannot take this digest. It has no NVIDIA driver, both active
  displays hang off the RTX 3070, and the variant that fixes that does not exist
  ([#40](https://github.com/ultus-net/dux-atomic/issues/40)).
- The graphical dogfood is still stale: the last recorded run was 2026-11-10 on
  `e12b116`.
- `.trivyignore` still carries 38 entries that match nothing on the new base. A
  local run of the CI flags exits 0, and a raw pass with no ignore file found 0
  CRITICAL/HIGH findings across 11 targets. That is not evidence the entries are
  obsolete: they stay until a reviewed change empties the file, and
  `tests/test-static.sh` fails on an empty ignore file.
- No script checks the kernel signature, so a base bump could ship an unsigned
  kernel and CI would stay green.

## Not proven by this promotion

A promoted tag proves build, package install, image lint, the VM boot with a
serial login, signature, SPDX attestation, SLSA provenance, and a blocking
vulnerability scan. It does not prove firmware accepts the chain, a bare-metal
install, a rendered desktop, rollback, the Xfce fallback, a second session,
gaming, or the NVIDIA path. See `docs/known-gaps.md`.

## Sources

- Run 43157860388, its jobs, and its step windows:
  `gh api repos/ultus-net/dux-atomic/actions/jobs/<id>` for each of
  130985772842, 130985892619, 130985892655, 130993180303, 130995548596, and
  130995722606.
- Artifact sizes:
  `gh api repos/ultus-net/dux-atomic/actions/runs/43157860388/artifacts`.
- Digests and layer counts: `skopeo inspect --format '{{.Digest}} layers={{len .Layers}}'`
  against `:latest`, `:sha-8b42a1116552dd12d82a9eb6f905f0bde3d7a5b9`, and
  `@sha256:3b72522f…`.
- The previous digest: `docs/research/2026-11-11-latest-promotion-2.md`.
  Its 261 layers are measured now, by inspecting that digest directly, because
  that record predates the measurement.
- Kernel and module signatures: `rpm -q`, a PE certificate-table parse of
  `vmlinuz`, `openssl pkcs7 -inform DER -print_certs`, and `modinfo -F signer`,
  run against the built image on 2026-11-12.
