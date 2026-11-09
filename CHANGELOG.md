# Changelog

## Unreleased

- Give the greeter compositor access to the video, render, and input device groups: copy the missing groups from `/usr/lib/group` into `/etc/group`, add `greeter` to them, and fail the build if the membership did not take effect.
- Disable Plymouth with `plymouth.enable=0`; with no usable display the boot waited forever in `plymouth-quit-wait`.
- Assert the greeter session in `tests/vm/boot-smoke.sh`: wait for `greetd` and a `Session c1 of User greeter` scope instead of a serial login prompt, then check the scope is still running after a settle period.
- Mask the portal service in the greeter user's real home, `/var/lib/greeter`, own that home in the tmpfiles rule, and check the rule in a scratch root at build time.
- Build the image from the Universal Blue image-template layout: a `ctx` stage, `build/common.sh`, `overlay/`, and `bootc container lint`.
- Install the first desktop set on `base-main:45`: niri, DMS 2.1.2, dux-greeter, Ghostty, and the Xfce X11 session; enable greetd.
- Add `tests/vm/make-disk.sh` and `tests/vm/boot-smoke.sh` for a headless qcow2 boot test, with a serial-console kernel argument in the overlay.
- Approve the dux-atomic design and scaffold the image definition from the Universal Blue image-template, based on `ghcr.io/ublue-os/base-main:45` on a floating tag for prototyping.
- Add `tests/test-static.sh`, a cheap check that the `Containerfile` builds from `BASE_IMAGE` and that the package manifest is one name per line.
- Document the proposed dux-atomic workstation design for generic Intel and NVIDIA hardware.
- Define existing dotfiles ownership, Omarchy-style conveniences, AI isolation, and hardware acceptance gates.
- Record that implementation and all workstation migrations await operator approval.
- Select a minimal Xfce-on-X11 fallback with independent session settings and recovery requirements.
- Capture live November 2026 theme-tooling and Fedora 45 compatibility research, including release revisions and untested integration gates.
- Add six workstation QoL requirements: staged-update visibility, NVIDIA suspend/resume, per-device power and display profiles, audio state, notification and clipboard discipline, and offline recovery.
- Split DevOps and junior-developer QoL between image-owned system capabilities and dotfiles-owned tools, templates, and preferences.
- Record grounded November 2026 research on agent-fleet security: system-level policy planes, fail-closed defaults, external audit records, executable supply-chain pinning, OS sandboxing, and memory provenance.
- Identify four enforcement gaps in the current dotfiles wiring: removable userland policy, an unpinned executable supply chain (42 skills with no ref, floating MCP and plugin launchers), host credential exposure, and no OS-level command sandbox.
- Revise the security research for a retained workflow-guard: pin 1.19.2, document the three enforcement seats, the audit-sink gap, the fail-open and fail-closed modes, and an external attendance canary.
- Add the November 2026 RSI and harness sweep: 43 dated sources, confirmations and contradictions of the existing loop, and the concrete edit list for the dotfiles reading list and playbook.
