# :latest promotion, 2026-11-11

`ghcr.io/ultus-net/dux-atomic:latest` moved to the digest of commit `d0ff8fd`,
the merge of PR #37. This is the first promotion through the pipeline, and the
first time `:latest` existed: every earlier run published only `sha-<commit>`.

## What moved

| Ref | Digest |
| --- | --- |
| `:latest` | `sha256:ce7f267f8add7879703fbb351a262261fbab997d4cfeaa5d2ff775224e69fbff` |
| `sha-d0ff8fd551bf691f542b1bfef140ebc3c94d3e0b` | `sha256:ce7f267f8add7879703fbb351a262261fbab997d4cfeaa5d2ff775224e69fbff` |
| `sha-04742e105d1e4cad3952ca6f580f4e93f62d6a07` (previous publish) | `sha256:994e707771ea9854a586c484b9eca58d477d0bf5407e9489aae5fdce7cba89d4` |

The two tags carry different digests because each names a different commit.

## The run

`workflow_dispatch` with `promote=true` on `main`, run
[43012620883](https://github.com/ultus-net/dux-atomic/actions/runs/43012620883),
at `d0ff8fd`:

| Job | Result | Time |
| --- | --- | --- |
| `static` | success | 12s |
| `signing` | success | 21s |
| `image` | success | 38m2s |
| `publish` | success | 12m47s |
| `verify` | success | 12s |
| `promote` | success | 15s |

`publish` recorded the pushed digest as a check-run annotation:
`pushed ghcr.io/ultus-net/dux-atomic@sha256:ce7f267f8add7879703fbb351a262261fbab997d4cfeaa5d2ff775224e69fbff`.

`verify` ran `cosign verify` and `cosign verify-attestation` in their own job
with `timeout-minutes: 20`, printed bounded prefixes, and uploaded the
`verify-logs` artifact (892,180 bytes). Run 43006883112, the previous publish,
uploaded the same artifact at 891,971 bytes.

`promote` ran `skopeo copy --preserve-digests` to `:latest` and then asserted
`skopeo inspect :latest` equals the publish digest. It is gated on both
`publish` and `verify`, so the tag moves only onto a digest whose signature and
attestation verified.

## Independent confirmation

A read-only pull token from `https://ghcr.io/token?scope=repository:ultus-net/dux-atomic:pull`
returned `Docker-Content-Digest: sha256:ce7f267f…` for both `/manifests/latest`
and `/manifests/sha-d0ff8fd…`. The package is anonymously pullable, so a target
machine needs no registry credentials to install it.

## Why the push run was cancelled

The merge of PR #37 queued push run `43012443015` at the same commit. A
dispatch at `main` runs the identical graph plus `promote`, so that push run was
cancelled 45 seconds in rather than spending a second 38-minute image build.
The concurrency group `ci-${{ github.ref }}` never cancels a running main run
(`cancel-in-progress` is `pull_request` only), so the dispatch queued behind it
and started when the push run was cancelled.

## Accepted at promotion

- The image shipped `console=ttyS0,115200` unconditionally, against
  `docs/known-gaps.md:3`. PR #41 merged after this promotion and moves the karg
  to the VM test disk only; the next promotion carries the fix.
- The graphical dogfood behind this digest is stale. The last recorded run was
  2026-11-10 on `e12b116`, before the first-login retry change.

## Not proven by this promotion

A promoted tag proves build, signature, attestation, VM boot, first-login units,
and a serial login. It does not prove a rendered desktop, a bare-metal install,
rollback, the Xfce fallback, a second session, gaming, or the NVIDIA path. See
`docs/known-gaps.md` and the NVIDIA plan in
`docs/research/2026-11-12-nvidia-variant-plan.md`.
