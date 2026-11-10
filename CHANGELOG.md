# Changelog

## Unreleased

- Provision the Dux desktop for a new account on its first graphical login: `dux-atomic-desktop.service` runs `dms setup headless --compositor niri --terminal ghostty --skip-existing` at `graphical-session-pre.target` unless the user already owns a niri config, and `dux-atomic-dms-defaults.service` seeds a dark DMS session background. A user preset enables both units, an image-level `niri.service.wants/dms.service` starts the shell on the first login, and both units skip root and the greeter. `boot-smoke.sh` starts the units after the console login and asserts the provisioned files and the image-level binding. The DMS session schema and setup contract are recorded in `docs/research/2026-11-10-dms-first-login.md`. The greeter keeps the upstream `dms-greeter --command niri` config because Fedora's greetd 0.10.3 does not ship a `greetd-spawn` binary.
- Add a login stage to the VM test: build the candidate disk with one test account, log in on the serial console, assert the account owns a session, and check the greeter's device groups on the running system. The assertion markers are emitted through `printf` so the echoed command cannot satisfy them. A lost console line is a warning when the guest still answers. The test account gets no admin groups, and credentials reject characters that would break the generated TOML. The image ships no interactive user, so a real install must create one.
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
