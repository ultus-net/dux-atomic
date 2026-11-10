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

## Live graphical login

The graphical dogfood ran on 2026-11-10 against image `3e886bc33a30` (commit
`e12b116`), from the qcow2 disk that `tests/vm/make-disk.sh` built for that
image. The VM booted a pristine disk (`-snapshot`) with `virtio-vga-gl` and a
GL-capable display, so the greeter rendered on a real GPU path.

Observed, in order:

1. The greeter showed a `Select user...` pill and the session dropdown read
   `Niri`, so the greeter seed selected the niri session on the first boot
   (`.vm/picker5/41-user-picker.png`).
2. A pointer click on the pill expanded the user list, and a click on the `dux`
   row at `(0.452, 0.464)` moved focus to the password field
   (`.vm/dogfood7/72-user-selected.png`).
3. The password plus Enter started the session. Arrow keys and Enter on the
   collapsed picker do nothing, so the pointer path is the only reliable one.
4. From the serial getty, which shares the login user's manager, the live units
   reported `DUX_LIVE_NIRI=active`, `DUX_LIVE_DMS=active`, `DUX_LIVE_USER=dux`.
5. The desktop showed the DMS bar, the DMS Welcome dialog, and the dark session
   background from the seed (`.vm/dogfood7/74-desktop.png`).

No manual `dms setup` ran at any point. The first graphical login provisioned
the desktop by itself.

The setup unit records success with `~/.local/state/dux-atomic/desktop-setup.done`.
`ExecCondition` runs the setup for a fresh home or for a dms-generated config
that has no marker, and skips a user-authored config. `ExecStartPost` writes the
marker only after `dms setup` exits 0, so a failed or timed-out run retries on
the next login. `tests/test-static.sh` runs the five condition fixtures.

The probe driver is `.vm/dogfood_login.py` with `DOGFOOD_PROBE=7`. It lives in
the ignored `.vm/` tree as run evidence and is not part of the image. The
tracked evidence is the marker output quoted above; the screenshots stay local.

Commits `98ef7d3` and `0307e9a` add documentation, test assertions, and a
tmpfiles comment. Commit `21c8874` adds the adversarial-review fixes in tests
and docs. The retry logic above changes `dux-atomic-desktop.service`, so the
image behind this dogfood predates it. Rebuild the image and re-run this
dogfood before promotion.

