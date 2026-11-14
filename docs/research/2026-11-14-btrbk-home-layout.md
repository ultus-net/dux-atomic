# btrfs layout for home snapshots (issue #68)

Status: evidence record, not a decision. Cutoff 2026-11-14. #68 asks for a
btrbk configuration that snapshots the home subvolume. This record measures what
the install path actually creates and shows there is no home subvolume to name,
so the configuration cannot ship until the layout is chosen. No package, unit,
timer, or configuration is added by this pull request.

## What this install path creates

`docs/install.md` installs with `bootc install to-disk --wipe --filesystem btrfs`
and no other layout argument. bootc's manual for that command documents the
partition layout and nothing below partition level:

| Architecture | Partitions the installer creates |
| --- | --- |
| x86_64, aarch64 | BIOS boot or ESP at least 512 MiB, `/boot` only under LUKS, root using the remaining space |

Quoted from `bootc-install-to-disk(8)`, Partition layout: "The installer creates
a GPT partition table with architecture-appropriate partitions. The exact layout
varies by architecture but generally includes" a boot partition, an ESP, "Boot:
Separate /boot partition, only created when using LUKS encryption", and "Root:
The root filesystem, using the remaining disk space".

Measured against the pinned base on 2026-11-14, which is what the install runs
from:

```
$ podman run --rm quay.io/fedora/fedora-bootc:45@sha256:42259b1db41a7f792a19cfd28e0c66e3e415392109a7d7095f292ad1e2a56453 \
    sh -c 'ls -ld /home /var/home /var'
lrwxrwxrwx 2 root root 8 Jan  1  1970 /home -> var/home
ls: cannot access '/var/home': No such file or directory
drwxr-xr-x 1 root root 6 Nov 13 22:59 /var
```

`/home` is a relative symlink to `var/home`, and the image creates no
`/var/home`. A user's home therefore lands inside the root filesystem under
`/var/home`, because that is where the symlink resolves. Nothing in the install
path gives it a subvolume of its own.

## btrbk processes subvolumes

btrbk has no way to snapshot a directory. Quoted from `btrbk.conf(5)`,
Description: "The btrbk configuration file specifies which btrfs subvolumes on
the filesystem are to be processed". Its `subvolume` section takes a "Subvolume
to be backed up, relative to the `<volume-directory>` of the volume section", and
its `volume` section takes a path "pointing to a btrfs file system containing the
source subvolume(s)".

A `subvolume home` line would therefore need a btrfs subvolume named `home`
under the volume directory. On this install path `/var/home` is a directory
inside the root filesystem, so that line names nothing and the timer would run a
configuration that snapshots nothing. The design anticipated exactly this: it
keeps snapshots "disabled until per-device paths, retention, and permission
policy are configured explicitly".

## What only a btrfs install of this image can answer

These describe a disk created by the installer. The repository also builds
such a disk as a qcow2 image: `tests/vm/make-disk.sh:82` writes a disk with
`--rootfs btrfs`, which produces a bootable qcow2 that contains a btrfs
installation of the image. An operator with root on the host can build that qcow2
and boot it under QEMU to run the checks below inside the guest.

The qcow2 comes from `bootc-image-builder` (`tests/vm/make-disk.sh:2`), while
`docs/install.md:15` installs the published image with `bootc install to-disk`.
If the two produce different layouts, the to-disk install is the authority.

| Question | Command |
| --- | --- |
| Is `/` itself a subvolume, and what is it called? | `btrfs subvolume show /` |
| Which subvolumes did the installer create? | `btrfs subvolume list /` |
| Is home a directory in root or a mount of its own? | `findmnt -no TARGET,SOURCE /var/home` |
| Does a snapshot restore one deleted file? | the drill in the design's recovery section |

## The three ways forward

| Option | What changes | What it buys | What it costs | What it cannot prove |
| --- | --- | --- | --- | --- |
| A. Give home its own subvolume | a repart.d `/home` definition or an explicit `to-filesystem` layout, plus the mount and the `/home` symlink | btrbk snapshots home alone, which is what the design asks for, and pruning stays small | a layout change on both targets, validated on a btrfs install, and the symlink has to keep resolving | nothing about disk failure, theft, or privileged compromise, which the design already excludes |
| B. Snapshot the root subvolume | btrbk `volume /` with a `subvolume` name once `/` is known to be one | no layout change, and the snapshot also covers `/etc` | every snapshot is a whole-root copy, so `/var` churn fills the disk faster and restore is coarser | whether `/` is a named subvolume at all is unmeasured here |
| C. Keep the gap | nothing | no false claim in the image | no recovery path until the decision is made | — |

Recommendation, not a decision: option A. The design asks for home recovery with
a defined retention (daily for seven days, weekly for four weeks), and option B
trades that for whole-root snapshots whose size the design never budgeted. The
choice is the operator's, and it needs the four measurements above from one
target before either option lands. These measurements may be taken on a VM
install of the image (see the Procedure section), but one to-disk install on a
real target must still confirm the same answers before the btrbk configuration
ships.

## Procedure

1. Build the test disk (requires root on the host). The script takes an image
   argument and an output directory. Run it like this:

   sudo tests/vm/make-disk.sh localhost/dux-atomic:dev output

   The produced disk will be written to output/qcow2/disk.qcow2.

2. Boot the resulting qcow2 under QEMU through the repository test harness.
   Export the test credentials (the defaults below match the values
   make-disk.sh creates) and run the documented entry point:

   export TEST_USER=dux TEST_PASSWORD=dux-test
   tests/vm/boot-smoke.sh output/qcow2/disk.qcow2 .vm/boot.log

   This is the documented usage at `tests/vm/boot-smoke.sh:17` and ensures the
   serial console markers and log layout the repository test helpers expect.

3. Inside the guest, run the three commands above and the restore drill from
   the design's recovery section, then capture their verbatim outputs.

4. Record the outputs in this document with the date and the disk digest. The
   qcow2 produced by `make-disk.sh` is the test artifact, and
   `sha256sum output/qcow2/disk.qcow2` prints the digest to record. Include the
   exact command lines and the full copy-paste of the outputs, so reviewers can
   verify them later.

## What this record does not prove

- No btrfs install was made from this image, so no subvolume list exists.
- btrbk was not run. The package resolves in the Fedora 45 repository as
  `btrbk 0.32.7-1.fc45` and ships `/usr/lib/systemd/system/btrbk.{service,timer}`
  plus `/etc/btrbk/btrbk.conf.example`, which is a package fact, not a working
  snapshot.
- No restore drill ran, and no file was recovered.
- The claim that `/var/home` sits in the root subvolume is inferred from the
  symlink and the documented layout, not read off an installed disk.

## Sources

| Source | URL | Fetched | Used as |
| --- | --- | --- | --- |
| bootc-install-to-disk(8) | https://bootc.dev/bootc/man/bootc-install-to-disk.8.html | 2026-11-14 | Quoted, partition layout |
| btrbk.conf(5) | https://digint.ch/btrbk/doc/btrbk.conf.5.html | 2026-11-14 | Quoted, subvolume sections |
| `docs/install.md` | this repository, line 33 | 2026-11-14 | Paraphrased, the install command |
| Pinned base image | `quay.io/fedora/fedora-bootc:45@sha256:42259b1d…a56453` | 2026-11-14 | Measured by command output above |
