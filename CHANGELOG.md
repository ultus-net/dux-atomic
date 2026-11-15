# Changelog

## Unreleased

- Schedule a weekly repin probe and a dispatchable write path: add `.github/workflows/repin-base.yml` to probe the pinned `Containerfile` digest weekly and open a human-reviewed PR to refresh it when the tag resolves to a different digest. The workflow probes by default and only writes on schedule or when dispatched with `apply: true`; it never merges the PR automatically. Refs #102.
- Audit linutil's catalogue at `2026.11.14` (`docs/research/2026-11-15-linutil-catalog-audit.md`): most entries are unreachable on a Fedora bootc image because linutil hides them behind a package-manager precondition, and three gaps are tracked as #111, #112 and #116.
