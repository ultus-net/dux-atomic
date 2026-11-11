# :latest promotion 2, commit 284942b

`ghcr.io/ultus-net/dux-atomic:latest` moved to the digest of commit `284942b`,
the merge of PR #53. This is the second promotion through the pipeline, and the
first whose build commit includes the CI hardening merged after the first one:
the apt retry and failover (#46), the hostname-anchored boot prompt (#50), the
raised boot budget (#50), the `verify` job split (#44), and the checkout in
`publish` and `promote` (#52).

## What moved

| Ref | Digest |
| --- | --- |
| `:latest` | `sha256:3b72522f1e85abb65d4bef055e23bc753189282158b89f24fd4e37d4c13b5593` |
| `sha-284942bdbec3e7c85915420cd2f4efc82ae19c16` | `sha256:3b72522f1e85abb65d4bef055e23bc753189282158b89f24fd4e37d4c13b5593` |
| `:latest` before this run (`d0ff8fd`) | `sha256:ce7f267f8add7879703fbb351a262261fbab997d4cfeaa5d2ff775224e69fbff` |

The tag skipped one publish: `sha-04742e105d1e4cad3952ca6f580f4e93f62d6a07`
published `sha256:994e7077…` and was never promoted, as the first promotion
record notes. `:latest` therefore went from `d0ff8fd` straight to `284942b`.

## The run

`workflow_dispatch` with `promote=true` on `main`, run
[43093996770](https://github.com/ultus-net/dux-atomic/actions/runs/43093996770),
at `284942b`:

| Job | Result | Time | Window |
| --- | --- | --- | --- |
| `static` | success | 16s | 20:10:43 to 20:10:59 |
| `signing` | success | 20s | 20:11:01 to 20:11:21 |
| `image` | success | 29m52s | 21:03:10 to 21:33:02 |
| `publish` | success | 13m13s | 21:33:08 to 21:46:21 |
| `verify` | success | 15s | 21:46:23 to 21:46:38 |
| `promote` | success | 19s | 21:46:43 to 21:47:02 |

The run was created at 20:10:27 and finished at 21:47:03, so 1h36m36s in total.
The fast jobs were done at 20:11:21 and the `image` job did not start until
21:03:10, so 51m49s of that total was spent waiting for an `image` runner. The
four jobs are independent of `static` and `signing`, which is why they finished
first instead of gating the queue.

### Where the image job's 29m52s went

| Step | Time |
| --- | --- |
| Free runner disk space | 1m47s |
| Install podman and qemu | 13s |
| Build image | 2m30s |
| Image lint and unit verify | 5s |
| Export image | 41s |
| SBOM | 4m21s |
| Upload SBOM | 6s |
| Build disk | 10m5s |
| Boot smoke test | 6m38s |
| Vulnerability scan | 2m30s |

`Boot smoke test` took 6m38s here. Run 43068532421 spent 42m53s in the same job
on the same TCG setting before failing on the login prompt, so boot wall clock
varies widely with the runner and the 1800s `BOOT_TIMEOUT` is what bounds it
rather than a figure any run measured as sufficient.

### Where publish's 13m13s went

| Step | Time |
| --- | --- |
| Download image | 9m51s |
| Download SBOM | 2s |
| Install podman and skopeo | 5s |
| Push the commit tag | 2m53s |
| Record the pushed digest | under 1s |
| Install cosign | 4s |
| Sign the digest | 3s |
| Attest the SBOM | 6s |
| Upload publish logs | 1s |

The 7,823,295,732-byte image artifact took 9m51s to download, which is most of
the job. Signing and attesting succeeded on their first attempt, so none of the
retry budget was spent. The pushed digest was recorded as a check-run
annotation:
`pushed ghcr.io/ultus-net/dux-atomic@sha256:3b72522f1e85abb65d4bef055e23bc753189282158b89f24fd4e37d4c13b5593`.

### Verify and promote

`verify` spent 1s on `Verify the signature`, 3s on `Verify the attestation`, and
1s uploading `verify-logs` (892,196 bytes). Both cosign checks ran on their first
attempt.

`promote` installed `skopeo` in 8s, logged in to GHCR in 2s, and spent 6s on
`Promote latest`. That step is the workflow's `skopeo copy --preserve-digests`
followed by an equality check on `skopeo inspect :latest`
(`.github/workflows/ci.yml`), and the job needs `publish` and `verify`, so the tag
moved onto a digest whose signature and SBOM attestation had already verified.

Artifact sizes from the run's artifacts API: `image` 7,823,295,732 bytes,
`verify-logs` 892,196, `sbom` 529,472, `publish-logs` 1,405, and
`trivy-report` 858.

## What blocked the earlier attempts

Three failures stood between the first promotion and this one. All three were in
CI, none in the image.

### The runner could not install packages

Run 43033654470 spent 67 minutes in `Install podman and qemu` before apt
reported `Temporary failure resolving 'azure.archive.ubuntu.com'`, so `publish`,
`verify`, and `promote` never ran. PR #47 replaced four inline installs with
`build/install-packages.sh`: three attempts inside a 300s budget, a 180s cap per
attempt, one fetch attempt per URI, and a failover that comments the Azure entry
out of the runner's mirror list after a failed attempt (#46).

Run 43052107613 showed the failover was needed: it spent the whole budget on
`Ign:` lines for the Azure mirror and never reached `archive.ubuntu.com`. The
same run showed an earlier design error, `Acquire::Retries=5`, which delays
failover because apt repeats every retry on the same URI.

The failover branch itself is exercised by no run cited here: run 43063233928
(`bc83348`) and this promotion's `image` build both reached the Azure mirror
directly, so `tests/test-static.sh` is the only check on that path so far.

### The boot test missed its own login prompt

Run 43068532421 built the image, started `greetd`, then failed `Boot smoke test`
after 42m53s. The captured `boot.log` ends:

```
fedora login: [  275.126011] clocksource: Watchdog remote CPU 1 read timed out
```

A kernel message landed on the getty prompt's line, and the test waited on
`login: *$`, anchored to end of line. Against the real log the old pattern
matched zero times and the hostname-anchored replacement matched once. PR #51
changed the match to `^[A-Za-z0-9._-]+ login: ` and raised the CI
`BOOT_TIMEOUT` to 1800s (#50).

### Publish could not find the package installer

Run 43082564852 was green through `static`, `signing`, and `image` (31m30s),
then failed `publish` in 1m24s:

```
Run build/install-packages.sh podman skopeo
build/install-packages.sh: No such file or directory
##[error]Process completed with exit code 127.
```

PR #47 had moved four inline installs onto the shared helper, and two of those
four jobs never check out the repository: `publish` was documented as running no
repository code, and `promote` installs `skopeo` the same way. The helper was
never in their workspaces.

PR #53 gives both jobs an `actions/checkout` first step with
`persist-credentials: false`, states the narrowed invariant in each job's
comment, and adds a `tests/test-static.sh` assertion that parses `ci.yml` per job
and reds when a job runs the helper with no checkout before it (#52). Run
against the pre-fix `ci.yml`, that assertion names both jobs.

## Independent confirmation

A read-only pull token from
`https://ghcr.io/token?scope=repository:ultus-net/dux-atomic:pull` returned
`Docker-Content-Digest: sha256:3b72522f1e85abb65d4bef055e23bc753189282158b89f24fd4e37d4c13b5593`
for both `/manifests/latest` and `/manifests/sha-284942bd…`. Both answered with
`application/vnd.docker.distribution.manifest.v2+json`, and the package stays
anonymously pullable, so a target machine needs no registry credentials.

## Accepted at promotion

- This digest carries no build-provenance attestation, because the run predates
  #5: the workflow at `284942b` attests the SBOM only. It is therefore the last
  promoted digest for which a signature and an SBOM attestation are the whole
  evidence chain.
- The graphical dogfood is still stale: the last recorded run was 2026-11-10 on
  `e12b116`, before the first-login retry change.
- The apt failover has not fired against a live outage since it merged.
- No disk encryption or Secure Boot policy is recorded. The options are in
  `docs/research/2026-11-12-luks-secureboot-policy.md`, and no decision exists.

## Not proven by this promotion

A promoted tag proves build, package install, image lint, signature, SBOM
attestation, a hosted VM boot with a serial login, the first-login units, and a
blocking vulnerability scan. It does not prove a rendered desktop, a bare-metal
install, rollback, the Xfce fallback, a second session, gaming, the NVIDIA path,
or build provenance. See `docs/known-gaps.md` and the NVIDIA plan in
`docs/research/2026-11-12-nvidia-variant-plan.md`.

## Sources

- Run 43093996770, its jobs, and its step windows:
  `gh api repos/ultus-net/dux-atomic/actions/jobs/<id>` for each job.
- Artifact sizes: `gh api repos/ultus-net/dux-atomic/actions/runs/43093996770/artifacts`.
- The digest for `:latest` and `sha-284942bd…`: registry token from
  `https://ghcr.io/token?scope=repository:ultus-net/dux-atomic:pull&service=ghcr.io`,
  then `HEAD /v2/ultus-net/dux-atomic/manifests/<ref>`.
- The previous digest and the unpromoted publish:
  `docs/research/2026-11-11-latest-promotion.md`.
- The three blockers: PR #47 (#46), PR #51 (#50), PR #53 (#52), and their
  `CHANGELOG.md` entries.
