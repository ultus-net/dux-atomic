# Hyprland session assessment

Date: 2026-11-10.
Status: decided. Work deferred.

Related: `docs/superpowers/specs/2026-11-09-dux-atomic-design.md`,
`docs/superpowers/plans/2026-11-09-dux-atomic-candidate-images.md`.

## Question

Should dux-atomic ship Hyprland as a third desktop session alongside niri and
the Xfce X11 fallback, and should the running Omarchy installation be its base?

## Decision

- Defer the Hyprland session until each variant has its own hardware acceptance
  record. The NVIDIA variant waits on NVIDIA UAT. The candidate images add no
  Hyprland session in the meantime: niri stays the Wayland session and Xfce the
  X11 fallback.
- Omarchy reuse means configuration and ergonomics only: keybind patterns,
  workflow habits, and theme values. Port them to niri through the dotfiles
  repository, which the spec already plans.
- No Omarchy installer, migration script, or package layer enters the image.

Tracking: the deferred work item lives in the plan's Downstream phases section.
The full trigger list is the Revisit triggers section below. The item becomes a
forge work item when the repository has a remote.

## Findings

| Area | Finding | Evidence |
| --- | --- | --- |
| Greeter support | The greeter binary accepts Hyprland; the shipped config still hardcodes niri, so a selector is future work | `dms-greeter --help` lists `--command` values `niri, hyprland, sway, scroll, miracle, mango, labwc, aqueous`; `/usr/share/doc/dms-greeter/README.md:145,173-180` documents multiple compositors and session selection; `dux-greeter-git-2.1.3` ships `examples/dms-hypr.lua` |
| Shell support | DMS adapts to Hyprland without a fork | `dms-2.1.2` ships `Services/HyprlandService.qml` (47635 bytes) beside `Services/NiriService.qml` (71320 bytes) |
| Fedora packaging | The image's enabled Fedora 45 repositories carry no Hyprland | Inside image `4bf1f261b34e`, `dnf5 repoquery --available hyprland` returns nothing; the `hyprland*` query returns only `hyprland-protocols-devel`, `hyprcursor`, `hyprgraphics`, `hyprutils`, and `hyprwayland-scanner-devel` |
| Package source | Hyprland for Fedora 45 comes from third-party COPRs | `sdegler/hyprland` and `pm4rcin/Hyprland` both publish a `fedora-45-x86_64` chroot whose `repodata/repomd.xml` returns 200, checked 2026-11-10 |
| Session wiring | The greeter launches exactly one compositor | `/etc/greetd/config.toml` sets `command = "/usr/bin/dms-greeter --command niri"` |
| Omarchy portability | Omarchy is an Arch distribution layer, not a config bundle | `pacman -Qi omarchy` 4.0.6 depends on `pacman-contrib`, `limine`, `snapper`, `sddm`, `uwsm`, and `omarchy-keyring`; `pacman -Ql omarchy` lists 1769 files including `install` and `migrations` |

The dominant risk is the package source, not compositor support. A volunteer
COPR is consumed at image-build time, so a bad package is baked into an
approved image and reaches the workstation on update, leaving rollback as the
recovery. The image itself keeps no COPR enabled after the build:
`build/common.sh` disables both Dux repositories before the final commit.

The cost is also structural. Hyprland adds a third session mode for the VM boot
test to prove, and it needs its own NVIDIA driver configuration work, separate
from niri's.

## Options considered

| Option | Adds | Why not now |
| --- | --- | --- |
| Hyprland as a third session, package from COPR | A session entry, a greeter selector, and a boot test per mode | Puts a volunteer repo on the build path before NVIDIA is proven |
| Defer with a recorded decision | This document and a plan entry | Selected |
| Vendor a pinned Hyprland RPM built in our CI | A build job and version-pin maintenance | Correct answer if Hyprland becomes a daily driver, not before |
| Port Omarchy ergonomics to niri only | Dotfiles configuration | Already the plan, and it answers the ergonomics goal without a third session |

## Revisit triggers

Any one of these reopens the decision:

- Every variant has its own hardware acceptance record, including NVIDIA UAT on
  the NVIDIA variant.
- Fedora packages Hyprland, or the dependency is vendored as a pinned RPM with
  a reproducible build.
- The greeter gains a tested session-selector path the VM test can assert.
- The operator wants to switch between niri and Hyprland on the same machine.

## Work a future implementation must do

- Add the compositor and its portal package to the shared manifest without
  adding a second portal owner.
- Disable the compositor's COPR before the final commit if one is used, as
  `build/common.sh` already does for the Dux repositories.
- Add the pre-configured compositor launcher and a greeter selector, since the
  current greeter config launches a single compositor.
- Extend the VM boot test, `tests/vm/boot-smoke.sh` today and planned as
  `tests/vm/boot-assert.sh`, to boot each mode and assert a live session per
  mode, on both variants.
- Validate the NVIDIA driver path with the compositor's own environment
  requirements before publishing.

## Sources

- COPR `sdegler/hyprland`:
  https://copr.fedorainfracloud.org/coprs/sdegler/hyprland/
- COPR `pm4rcin/Hyprland`:
  https://copr.fedorainfracloud.org/coprs/pm4rcin/Hyprland/
- Fedora COPR repodata checked for both projects:
  `https://download.copr.fedorainfracloud.org/results/<owner>/<project>/fedora-45-x86_64/repodata/repomd.xml`
- Package evidence read from `localhost/dux-atomic:dev`, image ID
  `4bf1f261b34e21f4428e17393fd83c081d5036444f6a26c31abedadebfdb5fcc`.
