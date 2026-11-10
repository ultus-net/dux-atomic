## What

One paragraph on what changes and why.

## Work item

Fixes #

## Verification

- [ ] `just check` passes
- [ ] The image build, disk build, and boot smoke test pass if a unit, package, or build input changed
- [ ] The graphical dogfood ran if the desktop or first-login path changed
- [ ] `CHANGELOG.md` and the affected docs are updated

## Failure contract

If this changes a write, send, or delete path, name the contract: retry, dead-letter, alert, or human review.
