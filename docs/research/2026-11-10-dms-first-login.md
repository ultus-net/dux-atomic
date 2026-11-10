# DMS first-login provisioning: November 2026 evidence

Cutoff: 2026-11-10. Verified inside `dux-atomic:dev` from commit `eb17029`
(image `00f1f0b88707`), which ships `dms 2.1.2-1.fc45`.

## Question

Does the first-login seed in `overlay/usr/share/dux-atomic/dms/session.json`
match the DMS session schema, and does `dms setup headless` produce the files
the units claim?

## Session schema

Run inside the image:

```bash
podman run --rm --entrypoint /bin/sh dux-atomic:dev -c '
  grep -n "wallpaperPath" \
    /usr/share/quickshell/dms/DCommon/Common/settings/SharedSessionSpec.js
  grep -n "sessionConfigVersion" \
    /usr/share/quickshell/dms/Common/SessionData.qml
  grep -n "isColorSource" \
    /usr/share/quickshell/dms/Modules/WallpaperBackground.qml
'
```

Output:

```
16:    wallpaperPath: {
19:    readonly property int sessionConfigVersion: 7
        property bool isColorSource: source.startsWith("#")
```

`SessionStore.parse` skips a key that is absent from `SPEC`, so the persisted
name must be `wallpaperPath`. `SessionData` exposes it at line 178 and reads
it through `getMonitorWallpaper`. `WallpaperBackground` treats a value that
starts with `#` as a colour, so the seeded `"#101418"` paints a dark surface
without a wallpaper file. `configVersion: 7` matches the running schema.

## Setup contract

Run inside the image as a fresh user with no display:

```bash
podman run --rm --entrypoint /bin/sh dux-atomic:dev -c '
  useradd -m -s /bin/bash fresh1
  runuser -u fresh1 -- /usr/bin/dms setup headless \
    --compositor niri --terminal ghostty --skip-existing
  find /home/fresh1/.config /home/fresh1/.local -maxdepth 4
'
```

The command exits 0 and writes:

- `~/.config/niri/config.kdl`
- `~/.config/niri/dms/{binds,alts,colors,cursor,input,layout,outputs,windowrules}.kdl`
- `~/.config/ghostty/config` and `~/.config/ghostty/themes/dankcolors`
- `~/.config/systemd/user/niri.service.wants/dms.service`

It does not write `~/.local/state/dms/session.json`, so the seed unit and the
setup unit cannot race on that file. `dms setup` refuses to run as root, which
is why the unit runs at `graphical-session-pre.target` as the login user.

## Greeter session default

The greeter builds its session list from `wayland-sessions` and `xsessions`
in asynchronous load order, then calls `selectSessionIndex(0)` when it has no
remembered choice. On this image that made the first login nondeterministic:
one boot opened Niri, another opened the Xfce session.

The greeter stores its choice in `/var/cache/dms-greeter/.local/state/memory.json`.
Read from the `dux-greeter` source (`core/internal/greeter/installer.go`):

```
LastSessionID        string `json:"lastSessionId"`
LastSessionDesktopID string `json:"lastSessionDesktopId"`
```

`GreeterContent.qml` selects the remembered desktop by its desktop-file
basename, and `rememberLastSession` defaults to true. Seeding
`{"lastSessionDesktopId": "niri.desktop"}` therefore selects
`/usr/share/wayland-sessions/niri.desktop` on the first login. A later
login overwrites the file, and `ConditionPathExists=!...memory.json` makes the
seed unit skip once a user has made a choice. The seed sets only the desktop
id because selection matches on it first; a greeter change that matched only
`lastSessionId` would need this seed revisited. An empty existing file also
counts as a choice, so delete the file to re-seed.

## Deferred

A live graphical session has not yet been booted from this image here. The
`tests/vm/boot-smoke.sh` stage starts both units after a console login and
checks the provisioned files and dependency edges; the graphical dogfood must
still confirm `systemctl --user is-active dms.service` and the rendered bar.
