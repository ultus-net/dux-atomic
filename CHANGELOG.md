# Changelog

## Unreleased

- Schedule a weekly repin probe and a dispatchable write path: add `.github/workflows/repin-base.yml` to probe the pinned `Containerfile` digest weekly and open a human-reviewed PR to refresh it when the tag resolves to a different digest. The workflow probes by default and only writes on schedule or when dispatched with `apply: true`; it never merges the PR automatically. Refs #102.
- Audit linutil's catalogue at `2026.11.14` (`docs/research/2026-11-15-linutil-catalog-audit.md`): most entries are unreachable on a Fedora bootc image because linutil hides them behind a package-manager precondition, and three gaps are tracked as #111, #112 and #116.
- Gate the NVIDIA variant on a path-filtered job (#94): add a `changes` path-filter step and an `image-nvidia` job that builds `Containerfile.nvidia` when any of these paths change: Containerfile.nvidia, manifests/packages-nvidia.txt, manifests/packages-common.txt, build/, overlay/, or tests/verify-image.sh. The `image-nvidia` verify step runs `tests/verify-image.sh --no-package-lock` so the common package lock comparison is skipped only for the variant until its own lock lands. The job runs on either a pull request or a push when the listed paths change; a manual dispatch always runs it. No publish, disk, boot, scan, export, or weekly scheduled run was added.
