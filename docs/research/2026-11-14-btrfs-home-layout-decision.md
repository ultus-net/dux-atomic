# btrfs home-layout decision (issue #68)

Status: decision record. Cutoff 2026-11-14. The operator chose the layout on that
date after reading `docs/research/2026-11-14-btrbk-home-layout.md`. This record
ships no btrbk configuration, no timer, and changes no install command.

## Decision

- **Layout: a dedicated `home` subvolume (option A).** The install path gains a
  home subvolume, and `btrbk.conf` names it with a `subvolume home` section.
- **Snapshots cover home only.** The root subvolume is not snapshotted, so a
  snapshot stays small and pruning keeps the retention the design asks for:
  daily for seven days, weekly for four weeks.
- **Nothing ships before the layout exists.** An image that ships a timer whose
  `subvolume home` line cannot resolve snapshots nothing and reports success,
  which is worse than shipping no timer.

## Why not snapshot the root subvolume

Option B needs no install-path change, but every snapshot becomes a whole-root
copy. `/var` churn fills the disk faster than home does, and the design never
budgeted that size (`docs/research/2026-11-14-btrbk-home-layout.md:68` through
`:75`). It also cannot be written down safely yet: whether `/` is a named
subvolume on an installed disk is unmeasured here (`:79` through `:88`).

The measurement that forces the issue: `/home` is a relative symlink to
`var/home`, the image creates no `/var/home`, and `docs/install.md:33` passes
only `--filesystem btrfs`, so home lives in the root filesystem
(`:1` through `:20`). btrbk processes btrfs subvolumes only.

## Preconditions before any configuration lands

Four measurements from one btrfs install of this image, which may be a VM
install; one to-disk install on a real target must still confirm the same
answers before the btrbk configuration ships (see
`docs/research/2026-11-14-btrbk-home-layout.md`, section
`## What only a btrfs install of this image can answer`):

| Question | Command |
| --- | --- |
| Is `/` a subvolume, and what is it called | `btrfs subvolume show /` |
| Which subvolumes did the installer create | `btrfs subvolume list /` |
| Is home a directory in root or its own mount | `findmnt -no TARGET,SOURCE /var/home` |
| Does a snapshot restore one deleted file | the drill in the design's recovery section |

If the install path still creates no home subvolume after the change, the
decision is unimplementable as written and comes back here.

## What this record does not do

- No btrfs install was made from this image, so no subvolume list exists.
- No `btrbk.conf` ships, no timer is enabled, and `btrbk` is not installed in
  the image (`docs/known-gaps.md:5`).
- No restore drill ran, and no file was recovered.
- The install change itself is not written: it needs a `repart.d` home
  definition or an explicit `to-filesystem` layout, plus the mount and the
  `/home` symlink that still resolves.

## Follow-up work

Issue #68 keeps the plan's remaining three items: write the btrbk configuration
for the home subvolume, enable the timer and assert it in the image job, and
record the restore drill. Before any of them, two items the plan does not
list: run the four measurements on a btrfs install of the image (a VM install
is acceptable for the measurements), and change the install path so a home
subvolume exists. The roadmap's Task 8 carries the same three items. One to-disk
install on a real target must still confirm the same answers before the btrbk
configuration ships.

## What would reverse this

A measurement showing the installer already creates a named home subvolume under
another name, or a decision to accept whole-root snapshots and their size. Both
are cheaper than this change, and both are settled by the table above.
