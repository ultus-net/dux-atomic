# Linutil catalogue audit (pin: 2026.11.14)

Status: audit record. Pin: `2026.11.14`, the newest tag in `ChrisTitusTech/linutil` (MIT, Rust TUI, scripts embedded via `include_dir!`).

The question this record answers: does linutil's catalogue contain procedures dux-atomic should own? It does not answer whether to ship linutil. No binary is added and no upstream script is run.

## How the catalogue was obtained

`git clone --depth 1 --branch 2026.11.14 https://github.com/ChrisTitusTech/linutil`, then read `core/tabs/{system-setup,security,utils}/tab_data.toml` and the scripts they reference. Entry counts at the pin, counted by `script =` in each tab's `tab_data.toml`: `system-setup` 37, `security` 4, `utils` 35.

The decisive structural fact is the per-entry precondition. Every Arch entry sits behind `command_exists pacman`, every Alpine entry behind `command_exists apk`, and the Debian and Ubuntu sub-tabs behind their own package managers. linutil hides those entries on a host without that package manager, so on a Fedora bootc image they are not merely unsuitable, they are unreachable. The UFW baseline is the same shape in reverse: its precondition is `command_exists firewall-cmd` matching **false**, so a host that ships firewalld never sees it.

## Verdict table

Fedora is the only sub-tab that can run here, so it carries the per-entry verdicts. The rest are graded as groups, with the precondition that hides them named.

| Entry or group | Upstream script at 2026.11.14 | What it changes | Verdict | Evidence |
| --- | --- | --- | --- | --- |
| FirewallD Firewall Baselines (CTT) | `core/tabs/security/firewalld-baselines.sh` | firewalld zones, services and rich rules via `firewall-cmd` | gap | `manifests/packages-common.txt:51` installs `firewalld` and ships no zone or service baseline; `overlay/etc` holds only `motd.d` and `xdg-desktop-portal` |
| Configure DNF | `core/tabs/system-setup/fedora/configure-dnf.sh` | `/etc/dnf/dnf.conf` defaults | gap | no `dnf.conf` under `overlay/`, and no build step writes one |
| Multimedia Codecs | `core/tabs/system-setup/fedora/multimedia-codecs.sh` | enables `rpmfusion-free` and `rpmfusion-nonfree`, installs codecs | gap | the base image enables no codec repository; `fedora-multimedia` reaches `Containerfile.nvidia` only, through the `negativo17` packages `manifests/packages-nvidia.txt:4` names |
| RPM Fusion | `core/tabs/system-setup/fedora/rpm-fusion-setup.sh` | `/etc/yum.repos.d/rpmfusion-*.repo` | covered by the row above | the repository is the mechanism and the codecs are the outcome, so one tracker holds both (#112); #113 is the duplicate |
| Btrfs Assistant, Snapper Config, grub-btrfs | `core/tabs/system-setup/fedora/fedora-btrfs-assistant.sh` | btrfs subvolume snapshots, snapper config, grub-btrfs | covered | #68 tracks local home snapshots; a second snapshot tracker would split one decision |
| Nvidia Proprietary Drivers | `core/tabs/system-setup/fedora/nvidia-proprietary-driver-setup.sh` | negativo17 drivers, akmod, signing | covered | `Containerfile.nvidia` plus `manifests/packages-nvidia.txt` already implement it; the signing gap is #95 |
| Upgrade to a New Fedora Release | `core/tabs/system-setup/fedora/fedora-upgrade.sh` | `dnf system-upgrade` | moot | a bootc image moves release with `bootc switch`, not by mutating its own root |
| Virtualization | `core/tabs/system-setup/fedora/virtualization.sh` | enables `libvirtd`, adds the user to `libvirt` | moot | the image ships `distrobox` and `flatpak` for workloads; nothing in the repo or the roadmap asks for libvirt |
| Hyprland JaKooLit | `core/tabs/system-setup/fedora/hyprland-kool-fed.sh` | installs and configures Hyprland | moot | the image ships `niri` as its compositor; a second session is a design change, not a port |
| Install Desktop Environment, Uninstall Desktop Environment | `core/tabs/system-setup/desktop-environments.sh` | interactive desktop installer | moot | the image is one fixed desktop; an interactive installer contradicts that |
| Lynis Security Audit, rkhunter Rootkit Scan | `core/tabs/security/lynis-audit.sh`, `core/tabs/security/rkhunter-scan.sh` | installs an audit tool, scans the running host, removes it | dotfiles | a per-machine audit action, not image content; a procedure belongs in the operator's repo |
| UFW Firewall Baselines (CTT) | `core/tabs/security/ufw-baselines.sh` | installs UFW and writes its rules | moot | the entry's own precondition hides it when `firewall-cmd` exists, which it does here; #116 tracks the firewalld baseline instead |
| Arch sub-tab, 15 entries (server setup, DWM-Titus, Hyprland JaKooLit, CachyOS repos and kernel, Chaotic-AUR, Linux Neptune, Nvidia drivers, Omarchy Rice, pacman config, paru, Snapper Snapshots, System Maintenance, Virtualization, Yay) | `core/tabs/system-setup/arch/*.sh` | pacman, bootloader and AUR changes | moot | sub-tab precondition is `command_exists pacman`; the entries are unreachable on Fedora, and the equivalents are the Fedora rows above |
| Alpine sub-tab, 1 entry | `core/tabs/system-setup/alpine/alpine-upgrade.sh` | `/etc/apk/repositories` | moot | precondition `command_exists apk` |
| Debian and Ubuntu sub-tabs, 2 entries | `core/tabs/system-setup/{debian,ubuntu}/*.sh` | apt installs | moot | those sub-tabs' package-manager precondition fails here |
| Monitor Control, 12 entries | `core/tabs/utils/monitor-control/*.sh` | `displayplacer`/`xrandr` display geometry | dotfiles | per-machine display layout belongs with the operator's compositor config; the sub-tab also requires an X11 session, which a niri session is not |
| Printers, 3 entries | `core/tabs/utils/printers/*.sh` | installs CUPS, Epson and HP drivers on the running host | moot | host package installs do not persist on an immutable root; a printer set belongs in the image manifest if it is ever wanted |
| User Account Manager, 5 entries | `core/tabs/utils/user-account-manager/*.sh` | creates users, groups, passwords | dotfiles | first-boot account actions belong to the operator's onboarding, not the image |
| Runtime host tools, 15 entries: Auto Login, Bluetooth Manager, Bootable USB Creator, Crypto tool, Locale Setup, Numlock on Startup, Ollama, Ramalama, Ramalama Model Manager, Service Manager, SSH Commands, SSH Samba, Timeshift Backup, US Locale Setup, WiFi Manager | `core/tabs/utils/*.sh` | services, packages and per-machine tools on a live host | dotfiles | operator-side tooling, not image content; `Locale Setup` is additionally hidden by `command_exists locale-gen`, and `Timeshift Backup` by `command_exists dnf` matching **false**, which is never true on Fedora |

## Not reached

The `applications-setup` and `gaming` tabs were not audited. They install application sets through the host package manager, which the `Printers` row already covers as a class, so reading them would not change a verdict. `utils` was read as a list with three entries read in full (`add_to_group.sh`, `samba-ssh-setup.sh`, `locale-us-setup.sh`); the remaining groups are graded by what their scripts install, not line by line. All 35 `utils` entries appear in the table above, graded by class.

## Trackers

Three gaps stand: #111 (`/etc/dnf/dnf.conf`), #112 (codec repository and codecs), #116 (firewalld baseline).

An earlier pass graded the Arch and Alpine entries as gaps and opened trackers for them. That grading was withdrawn. These trackers are superseded by this record and carry no work: #104, #105, #106, #107, #108, #109, #110, #113, #114, #115, #117, #118, #119, #120. Each id maps to a row above whose verdict is `moot`, `covered` or `dotfiles`. Closing an issue is a live operation, which an agent session cannot perform, so the operator closes them.

## Recommendation

Do not ship linutil and do not port its scripts. Three procedures are worth owning, each as a small image change rather than an imported script:

- a firewalld baseline, because the image installs `firewalld` and leaves it at the distribution default;
- `/etc/dnf/dnf.conf` defaults, because the image ships the package manager and no configuration;
- a codec decision, because only the NVIDIA variant reaches `fedora-multimedia` today.

The reusable finding is the precondition mechanism: linutil already encodes which entries apply to which host, so a future audit can start from `tab_data.toml` and skip every sub-tab whose precondition fails here.
