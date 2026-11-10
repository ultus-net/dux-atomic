# First login

The image never runs the Dux setup for root. On the first graphical session, `dux-atomic-desktop.service` runs `dms setup headless --compositor niri --terminal ghostty --skip-existing` as that user. It writes only under the user's home: the niri config, the DMS binds, the Ghostty config, and the `niri.service` binding for `dms.service`. A user who already has a niri config without the DMS includes, such as a dotfiles-managed account, skips the setup.

The unit records success with `${XDG_STATE_HOME:-$HOME/.local/state}/dux-atomic/desktop-setup.done`, matching the unit's `%S`. `ExecCondition` runs the setup for a fresh home or a dms-generated config without that marker, so a failed or timed-out run retries on the next login instead of leaving a half-written home skipped forever. The marker is written only after `dms setup` exits 0.

The desktop retry's failure contract is retry on the next login until it succeeds. Each attempt is capped at 120 seconds, and there is no attempt limit, so a permanently failing setup costs up to 120 seconds on every login. A cap is a pre-promotion follow-up. The greeter seed's contract is retry on the next boot, described below.

`dux-atomic-dms-defaults.service` seeds `~/.local/state/dms/session.json` with a dark DMS background, so the first session is not a blank compositor surface. Replace it with a wallpaper from the Dux library when you want the full documented look.

Both units are enabled through `overlay/usr/lib/systemd/user-preset/01-dux-atomic.preset`, which `build/common.sh` applies with `systemctl --global preset`. `dms.service` is not globally enabled: `overlay/usr/lib/systemd/user/niri.service.wants/dms.service` binds it to the niri session, so the shell starts for every niri login, including an account that already owns a niri config and skips the setup. The Xfce fallback never starts `niri.service`, so it never starts the Wayland shell. Both units skip root and the greeter account.

The greeter keeps the upstream `dms-greeter --command niri` config. Do not copy Zirconium's `[general] service = "greetd-spawn"` stanza: Fedora's greetd 0.10.3 does not ship a `greetd-spawn` binary.

The greeter picks session index 0 when it has no memory, and the desktop files load in asynchronous order. `dux-atomic-greeter-defaults.service` runs before `greetd.service` and seeds `/var/cache/dms-greeter/.local/state/memory.json` with `lastSessionDesktopId: "niri.desktop"`, so a fresh install always opens niri. A session remembered from a previous login still wins, and any existing file, including an empty one, is left alone; delete it to re-seed.

The seed is a `Wants=` dependency, not `Requires=`, so a failed seed does not block the login. Its failure contract is retry on the next boot with the result visible in the unit journal; greetd then falls back to the first session it loads, which may be the Xfce fallback. Check `systemctl status dux-atomic-greeter-defaults.service` after a first boot.

A real install creates the operator account itself, either in the installer or with `useradd -m`. The image never ships a login account or a password.
