# NVIDIA variant CI gating (issue #94)

Status: decision-input record, not a decision. Cutoff 2026-11-14. It changes no
workflow, containerfile, or test. Publishing the variant and booting it on
hardware are separate items in #94; this record does neither.

## Question

Which trigger should build `Containerfile.nvidia` in CI: every pull request, a
pull request filtered to the variant's inputs, or a scheduled run plus manual
dispatch?

## Measured costs

| Measurement | Value | Source |
| --- | --- | --- |
| `image` job wall time, PR #93 | 24m20s | run 43573052798, job 132381399271, 07:51:55Z to 08:16:15Z |
| Its `Build image` step (`Containerfile`) | 4m04s | same job, 07:55:35Z to 07:59:39Z |
| Its disk and boot steps | 7m35s and 3m46s | same job, `Build disk` and `Boot smoke test` |
| Runner preparation per job | 3m38s | 3m14s disk free, 24s package install |
| Local variant build | 28m47s, image `c4fd38cddb70` | `docs/research/2026-11-14-nvidia-variant-build.md` |
| Variant image size | 7.57 GB | `podman images`, `localhost/dux-atomic:nvidia` |
| Local generic image, for comparison | 5.74 GB | `podman images`, `localhost/dux-atomic:dev` |
| Jobs that read `Containerfile.nvidia` | 0 | `git grep -i nvidia -- .github/` is empty |

`.github/workflows/ci.yml:92` builds the default `Containerfile`. The `image`
job then runs `tests/verify-image.sh`, exports the image, builds a qcow2, and
boots it under TCG. None of that reads the variant, and the disk and boot steps
alone are 11m21s of the job's 24m20s. A variant job scoped to build and verify
pays the 3m38s preparation plus its own build.

All three options below run the same job: build `Containerfile.nvidia`, then run
`tests/verify-image.sh`. None builds a disk, boots it, exports it, scans it, or
publishes it. The build fails on a missing module through
`build/check-nvidia-modules.sh`, which `build/common.sh:78` runs.

The hosted variant build time is unmeasured. The only build measurement is the
local 28m47s, while the hosted generic build step is 4m04s, so the first hosted
variant run is what bounds this.

## Options

| Option | Runner minutes added | What it proves | What it cannot prove | Failure mode when the variant bit-rots |
| --- | --- | --- | --- | --- |
| (a) Every pull request | about 32m per PR: 3m38s preparation plus the build, 28m47s local | Every PR head builds the variant against that PR's shared files | No GPU, no Secure Boot, no scan, no publish | The next unrelated PR reds and blocks merge, so the cheapest fix becomes removing the check |
| (b) Filtered to `Containerfile.nvidia`, `manifests/packages-nvidia.txt`, `build/*nvidia*`, and the shared build files | 0 on PRs that touch none of those paths, otherwise the same as (a) | A PR that changes the variant or a shared build input builds it before merge | Same as (a), and nothing at all when no filtered path changes | Silent: repository drift changes no path, so the job stays green by absence, and the filter is a second input list that drifts from the build's real inputs |
| (c) Schedule plus manual dispatch | 0 per PR, about 32m per run: 2.4 runner hours a month at weekly | The variant still builds against live repositories on that date, with no PR involved | No GPU, no Secure Boot, and no PR attribution | Found up to one period late; a red scheduled run has no PR owner and is easy to ignore; a manual run covers only what someone remembers |

The PR critical path changes less than the runner minutes. Jobs run in parallel,
so (a) adds roughly the difference between the variant job and the existing
24m20s job, about 8m at 32m, and more if runner concurrency queues it. It also
doubles the runner minutes the PR spends.

## Recommendation, not a decision

- **Take (b) as the merge gate.** A change that can break the variant is a change
  to its containerfile, its manifest, the shared build path, or the verify
  script. Those changes should fail in the PR that makes them, and unrelated PRs
  should not pay half an hour of runner time.
- **The path list must name every shared input, not just `build/*nvidia*`.** The
  variant runs the whole of `build/common.sh` and reads
  `manifests/packages-common.txt`, `overlay/`, and `tests/verify-image.sh`, so
  those belong in the filter beside `Containerfile.nvidia` and
  `manifests/packages-nvidia.txt`. A filter naming only the variant-named files
  misses the code most likely to break it.
- **Add (c) as a weekly drift net.** (b) cannot see a repository retire a package
  or a base tag move its kernel. The weekly run is the only option that catches
  that, at about 2.4 runner hours a month.
- **Keep the job to build and verify.** SBOM, export, disk, boot, scan, and
  publish stay out. The variant image is 1.83 GB larger than the local generic
  image, and none of those steps is what this gate is for.

The operator decision needed: approve `image-nvidia` as a required check with
that path list, and approve or refuse the weekly run, naming who owns a red one.
Without an owner, (c) is noise. The same decision fixes whether the variant job
adds the boot smoke, an unmeasured 11m21s at PR #93's rates.

## What this record does not prove

- CI cannot boot the variant on a GPU. A hosted runner has no GPU and no
  `/dev/kvm`, so the existing boot smoke is TCG and headless.
 - CI cannot prove Secure Boot. The modules carry an empty signer
  (`docs/research/2026-11-14-nvidia-variant-build.md`), so a Secure Boot machine
  refuses them until a local MOK enrollment (#95).
- The 28m47s build and 7.57 GB image are one local cold build. The hosted wall
  time, disk headroom, and image size after a hosted build are unmeasured.
- A build-and-verify job does not prove the variant boots or that the driver
  loads. Those are the hardware boot item in #94.
- No assertion reads the variant's userspace package set back out of the image.
  The job would prove the `dnf5 install` command exits 0, not that every name in
  `manifests/packages-nvidia.txt` landed. The lock file in #94 is that gate.
- The 5.74 GB comparison is the local `dux-atomic:dev` image, not what a hosted
  runner builds, so the 1.83 GB delta is directional.
