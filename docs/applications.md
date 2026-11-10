# Applications

The image ships the applications that need the operating system: Steam and its graphics stack. User GUI apps come from Flathub at first login, installed by the [dotfiles repository](https://github.com/ultus-net/dotfiles), so they update on their own cadence and stay out of the OS image.

## Delivery split

| App | Source | Reason |
| --- | --- | --- |
| Steam | Image, `steam` RPM | Needs the 32-bit graphics stack and the device rules the OS owns |
| Lutris | Image, after the gaming dogfood | Runs the same Wine, DXVK, and Vulkan stack as Steam, so it ships beside it |
| Zed | Flathub at first login | Editor releases move faster than the image |
| Bitwarden | Flathub at first login | Desktop vault and browser integration belong to the user session |
| Obsidian | Flathub at first login | Notes and plugins are user-owned data |
| Zen Browser | Flathub at first login | Browser cadence is far faster than the image |
| Discord | Flathub at first login | Proprietary chat client with no OS integration |
| Spotify | Flathub at first login | Proprietary media client with no OS integration |

## Steam licence

Steam is proprietary. The package spec in RPM Fusion permits redistribution of the Linux client, so the image may ship the RPM; redistribution does not relicense it, and the client stays under Valve's terms. `steam-1.0.0.87-4.fc45` comes from the already-enabled `fedora-multimedia` repository. Fedora's own repositories do not carry the client.

## Measured cost

`dnf5 install --assumeno steam` resolves to 249 packages, 226 MiB downloaded and 779 MiB installed. Steam needs a 32-bit userspace, which Fedora 45 ships, and `fedora-multimedia` publishes matched i686 and x86_64 mesa 26.2.6, so the 32-bit Vulkan driver tracks the 64-bit one. `tests/verify-image.sh` asserts that `steam` and `mesa-vulkan-drivers.i686` are installed in the built image.

Lutris follows in a later commit, after the gaming dogfood. The NVIDIA variant is a separate change.
