# Fedora 45 desktop compatibility audit

Cutoff: 2026-11-09. Research agent: OpenRouter anthropic/claude-sonnet-5.5.
This is a condensed record of the agent's live primary-source research.
Package and source observations below are agent-reported, not boot-tested.
No workstation was changed.

## Outcome

The selected Xfce-on-X11 fallback has current Fedora 45 packages.
Dux Greeter's observed X11 launch path has a session-type bug that prevents calling the integration ready.
The image also needs deliberate dependency selection and a single update owner.

## Dated evidence

| Item | Agent-observed version or revision | Evidence |
| --- | --- | --- |
| Xfce stable | 4.20, released 2024-12-15, still current at cutoff | https://www.xfce.org/download and https://archive.xfce.org/xfce/ |
| Xfce 4.22 roadmap | Modified 2026-11-03, no release dates set | https://wiki.xfce.org/releng/4.22/roadmap |
| Fedora 45 release tree | Compose Fedora-45-20261028.1, updates metadata dated 2026-11-09 | https://dl.fedoraproject.org/pub/fedora/linux/releases/45/ and https://dl.fedoraproject.org/pub/fedora/linux/updates/45/ |
| Fedora Xfce session | xfce4-session-4.20.4-2.fc45.x86_64, built 2026-08-01 | Fedora 45 RPM metadata and extracted RPM contents |
| Fedora Xorg | 21.1.24-2.fc45 release, 21.1.25-2.fc45 updates | Fedora 45 RPM metadata |
| Fedora xinit | xorg-x11-xinit-1.4.3-6.fc45 | Fedora 45 RPM metadata |
| Fedora niri | 26.04-2.fc45, upstream released 2026-04-25 | https://github.com/niri-wm/niri/releases/tag/v26.04 and Fedora RPM metadata |
| DMS | v2.1.2, 2026-11-08, commit 43255a46ea01e9d0de1fe8ce9897c0d71566b2a8 | https://github.com/duxlabs-dev/dux-shell/releases/tag/v2.1.2 |
| Dux Greeter | v2.1.2, 2026-11-08, commit c1e6a0352d56 | https://github.com/duxlabs-dev/dux-greeter/releases/tag/v2.1.2 |
| DMS Fedora 45 build | COPR 11287728, dms 2.1.2-1 | https://copr.fedorainfracloud.org/coprs/duxlabs/dms/build/11287728/ |
| Greeter Fedora 45 build | COPR 11287741, dux-greeter 1:2.1.2-1 | https://copr.fedorainfracloud.org/coprs/duxlabs/dux-repo/build/11287741/ |
| ublue base-main | 45.20261109.1, created 2026-11-09T03:11Z | ghcr.io/ublue-os/base-main:45 manifest and image labels |

The agent observed this base digest, not a permanent build pin:

```text
sha256:66f35026d4eb26c767302c69c7a2a1b9b031fa0edd933ec9405380a6abc39091
```

The observed 45 and latest tags resolved to the same digest. No stable tag existed.
The recipe should use a major-specific tag plus an independently verified digest, not a floating latest tag.
Source: https://github.com/ublue-os/main, observed HEAD 905f4a659d03 dated 2026-11-09.

## Integration findings

### Xfce and X11 login

The agent inspected Fedora's xfce4-session RPM.
Its xfce.desktop launches startxfce4, which invokes xinit if DISPLAY is unset.
Xorg and xinit are not guaranteed by installing xfce4-session alone.
The fallback must explicitly include its window manager, panel, desktop, input, lock, power, portal, and X server dependencies.
Avoid the experimental Xfce Wayland session and unintended extra greeter entries.

Dux Greeter scans both xsessions and wayland-sessions and executes the selected desktop entry.
Its v2.1.2 source nevertheless supplies XDG_SESSION_TYPE=wayland for all sessions.
The agent traced the launch through greetd/PAM: session registration can therefore occur with the wrong type.
A wrapper exporting x11 after login would not repair the earlier PAM/logind registration.

Sources:

- https://github.com/duxlabs-dev/dux-greeter/tree/v2.1.2
- https://git.sr.ht/~kennylevinsen/greetd/tree/master/item/greetd/src/session/worker.rs
- https://man.sr.ht/~kennylevinsen/greetd/

Decision gate: retain Dux Greeter only after correct session registration and both launch paths are demonstrated.
An upstream fix, narrowly maintained patch, or different tested login integration may be needed.
Do not choose an alternative or claim that an environment wrapper alone solves this without testing.

Required tests: loginctl session type, application environment, VT ownership, Xorg launch on Intel and NVIDIA, lock/resume, and repeated session switching.

### DMS dependencies and session separation

The agent found DMS v2.1.2 uses a Quickshell AppId pragma introduced in 0.3.0.
Fedora's observed package was an older 0.2.1-based snapshot, while the Dux COPR offered 0.3.2-2.
This is a source-level compatibility warning, not an observed launch failure.
Resolve a tested DMS/Greeter/Quickshell combination with verified package origins.

Fedora niri weak dependencies include several tools that duplicate DMS functions.
Inspect the dependency transaction rather than blindly installing its recommended bar, launcher, and lock stack.

Xfce autostart files mostly use OnlyShowIn=XFCE.
However, xfce4-notifyd also provides global D-Bus notification activation.
Test notification ownership in both sessions. Do not globally mask a service required by the fallback session.
Use session-specific portal and environment configuration, not global exports that alter both desktops.

### Updates and inherited defaults

The inspected ublue source enables rpm-ostreed-automatic.timer with staging policy, plus Flatpak update timers.
DMS v2.1.2 has an rpm-ostree updater backend.
The upstream bootc fetch/apply unit invokes an apply path that can reboot.
A custom bootc updater cannot be added without reconciling those inherited services.

Sources:

- https://github.com/ublue-os/main/blob/905f4a659d03/build_files/post-install.sh
- https://github.com/ublue-os/packages
- https://github.com/duxlabs-dev/dux-shell/tree/v2.1.2
- https://bootc-dev.github.io/bootc/bootc-upgrades.7.html

Design requirement: one OS staging owner, no unattended reboot, DMS mutation controls matched to the pinned release, and explicit Flatpak update ownership.
The exact timer/service implementation remains a test-gated implementation choice.

## Limitations

- No VM or physical boot was performed.
- NVIDIA Xorg launch and rootless Xorg behavior remain unverified.
- Koji, Bodhi, and the official GA announcement were blocked by Anubis. The agent used published repository trees and RPM metadata instead.
- Availability of an RPM does not establish a valid installation transaction or runtime compatibility.
- Dux Greeter hardcoding is source-observed. Its practical application/backend effects were not reproduced.
- SELinux image-build behavior, greeter RPM scriptlets, and policy changes require testing.
- Latest release tags and package repositories can change after this cutoff.
