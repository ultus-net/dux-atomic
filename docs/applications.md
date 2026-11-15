# Applications

The image ships the applications that need the operating system: Steam and its graphics stack. User GUI apps come from Flathub at first login, installed by the [dotfiles repository](https://github.com/ultus-net/dotfiles), so they update on their own cadence and stay out of the OS image. Terminal, developer, and sysadmin tools follow a separate split, recorded in [Developer and sysadmin tooling](developer-tooling.md).

## Delivery split

| App | Source | Reason |
| --- | --- | --- |
| Steam | Image, `steam` RPM | Needs the 32-bit graphics stack and the device rules the OS owns |
| Lutris | Image, after the gaming dogfood | Runs the same Wine, DXVK, and Vulkan stack as Steam, so it ships beside it. This supersedes the design spec's line that put Lutris in the Flatpak manifest |
| Zed | Flathub at first login | Editor releases move faster than the image |
| Bitwarden | Flathub at first login | Desktop vault and browser integration belong to the user session |
| Obsidian | Flathub at first login | Notes and plugins are user-owned data |
| Zen Browser | Flathub at first login | Browser cadence is far faster than the image |
| Discord | Flathub at first login | Proprietary chat client with no OS integration |
| Spotify | Flathub at first login | Proprietary media client with no OS integration |

## Steam licence

Steam is proprietary. The Steam spec in RPM Fusion permits redistribution of the Linux client, so the image may ship the RPM; redistribution does not relicense it, and the client stays under Valve's terms. `steam-1.0.0.87-4.fc45` comes from RPM Fusion nonfree, so the permission travels with the package the image installs. Fedora's own repositories do not carry the client. Until #112 the image took that package from negativo17's `fedora-multimedia`, whose rebuild of the same spec carried the same permission.

## Measured cost

`dnf5 install --assumeno steam` on the pinned base with RPM Fusion free and nonfree enabled resolves 462 packages, 190 of them i686, for 393 MiB of inbound packages and about 1 GiB of extra disk, with one replacement of `dbus-libs`, so the install is not purely additive. Steam needs a 32-bit userspace, which Fedora 45 ships, and Fedora publishes `mesa-vulkan-drivers` for both i686 and x86_64, so the 32-bit Vulkan driver tracks the 64-bit one. The figure replaces the pre-migration one, which was measured against a repository the image no longer enables and a base state the RPM Fusion transaction does not reproduce. `tests/verify-image.sh` asserts that every package the gaming group names is installed in the built image: `steam`, `gamescope`, `mangohud`, `steam-devices`, and `mesa-vulkan-drivers.i686`.

Lutris follows in a later commit, after the gaming dogfood. The NVIDIA variant is a separate change.
