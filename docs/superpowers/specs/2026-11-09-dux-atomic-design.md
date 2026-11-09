# dux-atomic workstation design

Status: proposed, awaiting operator approval.
Date: 2026-11-09.

## Intent

Build a personal Fedora bootc workstation image family for a developer desktop and work laptop.
Combine Universal Blue's quality-of-life base, the Dux desktop, and useful Omarchy workflows.
Keep personal configuration mutable and owned by the existing dotfiles repository.
Make project-scoped AI development intuitive without claiming immutability protects personal data.

## Operator decisions

- Repository and image name: dux-atomic.
- Base: Universal Blue base-main, pinned to Fedora 45 rather than a floating major.
- Primary desktop: niri, Dux Modular Shell (DMS), Dux Greeter with greetd, Ghostty.
- Backup desktop: a minimal Xfce on X11 session, explicitly selected at login.
- Gaming: native Steam RPM, gamescope, MangoHud, appropriate Vulkan and 32-bit graphics libraries.
- Applications: Zed, OpenCode, Discord, Spotify, Bitwarden, Obsidian, Zen Browser, Lutris.
- Developer convenience: rootless Podman and Distrobox.
- Agent safety: intuitive project-scoped rootless containers. The existing assistant also runs on a development server.
- Optional workstation access: dedicated agent account with no sudo, restricted through tailnet policy.
- Home recovery: local btrbk snapshots. These are not off-machine backups.
- Updates: automatically fetch and stage approved OS releases, activate on the operator's next reboot.
- Configuration: start with DMS defaults, then port useful Omarchy ergonomics.
- Desktop migration: wipe only after a verified external backup and explicit installation confirmation.

## Goals and non-goals

Goals:

- One shared build definition with generic and NVIDIA variants.
- Reliable monitors, docking, suspend, development, and Steam gaming on real hardware.
- Signed OS delivery with enforced verification and a documented recovery path.
- Config changes without an OS rebuild.
- Easy experimentation with user tools and containers.
- Existing OpenCode agents, skills, commands, plugins, and safeguards survive migration.

Non-goals:

- A fork of Zirconium, Omarchy, Fedora, or Universal Blue.
- An Arch compatibility layer or wholesale port of Omarchy administration scripts.
- Automatic restoration of personal files through OS rollback.
- Protection from all container escapes or malicious code running as the desktop user.
- Guaranteed anti-cheat compatibility. Each game's Linux support remains decisive.
- A public distribution with an installer, support organization, and independent package repositories in the first version.

Anti-goals:

- Two competing owners for the same configuration or executable.
- Agents with passwordless sudo, unrestricted host-home mounts, or container-management sockets.
- A successful container build being treated as proof that docking or NVIDIA works.
- Image updates overwriting personal desktop configuration.

## Approaches considered

| Approach | Benefit | Cost | Decision |
| --- | --- | --- | --- |
| Universal Blue base-main plus our desktop | Existing codecs, hardware conveniences, container tools, and no inherited full desktop | We assemble and test DMS and NVIDIA integration | Selected for QOL and ownership |
| Official Fedora bootc plus our desktop | Minimal upstream opinions | More hardware and multimedia integration work | Not selected |
| Derive from Zirconium | DMS/niri and NVIDIA variants already assembled | Additional project opinions and dependency | Reference only, no fork |

Base-main remains an upstream dependency with a changing support scope.
The project must monitor its lifecycle rather than assume indefinite support.
Changing the base later requires package, kernel, service, and hardware revalidation, not merely changing FROM.

## Hardware and migration constraints

| Machine | Observed state | Target |
| --- | --- | --- |
| Desktop, tailnet name omarchy | Omarchy 4.0.6, RTX 3070, AMD integrated GPU, both active monitors on NVIDIA, Secure Boot disabled | NVIDIA variant |
| Laptop, tailnet name bluefin | Bluefin 44 stable, Intel Arrow Lake-U graphics, attached Titan Ridge Thunderbolt bridge | Generic variant |

The operator confirms the laptop's external monitors work today.
Thunderbolt enumeration alone does not prove the dock's display topology or exclude every DisplayLink device.
Record laptop model, actual dock model, attached USB devices, monitor modes, and Secure Boot state before deployment.

Laptop encryption, employer policy, rollback deployment, network enrollment, and firmware requirements are migration preflight checks.
The desktop cannot switch from Arch directly with bootc.
Its migration requires an atomic installation path tested against the target image.
Do not assume an arbitrary intermediate installation preserves all target requirements.

The laptop stays on Bluefin until the generic image passes VM testing and hardware UAT.
The desktop stays on Omarchy until external backup restoration and NVIDIA UAT have a credible test path.
No disk erase, rebase, enrollment change, or reboot is authorized by this document.

## Ownership boundaries

```text
Universal Blue base-main, Fedora 45, verified digest
                 |
       dux-atomic image repository
       common desktop + generic/NVIDIA builds
                 |
       signed candidate image -> UAT -> stable channel
                 |
       bootc host, immutable /usr
          |                     |
          |                     +-- rootless project agent container
          |                         approved repo only, separate home
          |
          +-- mutable user configuration
              existing dotfiles repository
              OpenCode golden tree, Zed, shell, personal desktop overrides
```

### This repository owns

- Container build definitions, Fedora-major selection, and base digest pins.
- OS services, compositor dependencies, native Steam, graphics integration, and container prerequisites.
- Vendor desktop defaults and their versioned configuration contract.
- Image build, verification, signature policy, release channels, and system recovery documentation.
- An intuitive entry point for project-scoped agent containers.
- Explicit application bootstrap manifests for this image profile.

### Existing dotfiles repository owns

Repository: https://github.com/ultus-net/dotfiles.
Local checkout: /home/csh/Projects/dotfiles.

- install/opencode remains the single golden source for the OpenCode fleet.
- Existing OpenCode configuration, agents, commands, skills, and plugin wiring are not recreated in the image repository.
- Zed settings, shell fragments, git defaults, and personal overrides remain user-level configuration.
- The distro retains ownership of .bashrc and .bash_profile.
- Stage 30 deploys settings conservatively. Existing differing files are not overwritten automatically.
- Credentials, runtime state, sessions, and SSH keys remain outside images and tracked configuration.

The dotfiles checkout currently has an unrelated .gitconfig modification on feature/hermes-standards-adoption.
Do not reuse that branch for image integration or overwrite that modification.
Any necessary dotfiles changes use a separate issue, branch, review, and PR.

### Conflicts to resolve before implementation

The current packages/system.txt declares Bazzite, not this image.
The current Brewfile installs opencode-ai through npm and includes many GNOME applications.
Do not run the complete existing bootstrap unchanged and call the result reconciled.

Provide an explicit dux-atomic package profile rather than changing the default profile for other machines.
Prefer the existing Homebrew tool ownership where it already works.
Do not additionally bake the same user CLI into /usr without deliberately retiring its previous owner for this profile.
OpenCode must have one executable owner per environment and a tested version compatible with the existing fleet.
Native versus user-level OpenCode packaging is an implementation validation decision, not a reason to replace its configuration.

Initial configuration deployment uses the existing settings stage after a dry run.
No unattended FORCE=1 operation is permitted.
Desktop personal overrides may extend the dotfiles deployment in a separately tested change.
Image defaults must never compete with dotfiles-managed paths.

## Package and application policy

| Layer | Contents | Ownership |
| --- | --- | --- |
| Image | niri, DMS, greetd, Ghostty, portals, polkit integration, audio, network, Bluetooth, firmware tools, Steam, graphics, Podman, Distrobox, Tailscale, snapshot tooling | Image recipe |
| User GUI apps | Discord, Spotify, Bitwarden, Obsidian, Zen Browser, Lutris | Explicit Flatpak manifest with verified IDs and origin |
| Editor | Zed | Prefer native packaging for terminal/LSP/toolchain integration, verify current supported distribution method |
| User CLI | Existing Brewfile tools, OpenCode, git helpers, shell navigation | Dotfiles profile, no duplicate executables |
| Project toolchains | Project-specific language SDKs and build tools | Rootless development containers or existing version manager |

The prior blanket proposal to use a Zed Flatpak is not binding.
Editor integration with the existing workflow matters more than claiming a sandbox while granting broad filesystem access.
Flatpak repository origin and application verification status must be checked individually.
Do not describe every Flathub package as an official upstream release.

Use established Flatpak installation mechanisms and a tested idempotent bootstrap.
Do not assume /etc/flatpak/preinstall.d is supported without identifying the service that consumes it.
Application installation requires an explicit operator action and a visible result.
Partial failures remain visible and a retry converges without reinstalling successful applications.

Proposed small convenience additions: lazygit, btop, yazi, and common CLI search/navigation tools.
Reuse existing atuin, starship, zoxide, fd, ripgrep, and similar tools from dotfiles.
Do not introduce a second shell, multiplexer, or SDK manager merely for novelty.
Keep bash and tmux initially. Additional tools remain optional.

### Ad-hoc system packages

Distrobox is the convenient path for experiments and user tools.
Permanent host dependencies belong in the image recipe and land through reviewed rebuilds.
User-space applications can be installed without rebuilding the OS.

Do not promise unrestricted rpm-ostree layering on a bootc-managed host.
The implementation must verify the exact base's supported local-package mechanism and its effect on bootc updates.
If supported local layering disrupts bootc management, keep it an explicitly documented break-glass workflow, not the default.
The operator gets flexible software installation without an untested mixture of update managers.

## Omarchy-to-Dux QOL map

Carry over workflows and ergonomics, not implementation-specific daemons.
Use DMS built-ins first, avoiding duplicate launchers, notification services, clipboard managers, and lock screens.

| Current convenience | Target experience | Acceptance check |
| --- | --- | --- |
| Launcher and discoverable menus | DMS launcher and a searchable shortcut/help entry | Apps, settings, and common commands are keyboard-accessible |
| Familiar app shortcuts | niri bindings for terminal, browser, Zed, files, screenshots, lock, and workspaces | Publish a short mapping and resolve collisions |
| Coordinated application themes | DMS theming and supported Ghostty/GTK/Qt integration | Theme changes work without overwriting personal configuration |
| Clipboard and emoji access | DMS-supported features where available | Copy/paste works across native, Flatpak, and XWayland apps |
| Screenshots and annotation | DMS capture plus an annotator only if needed | Region capture, clipboard result, and save path work |
| Screen sharing and recording | Correct niri desktop portal stack and supported capture tool | Browser and Discord screen sharing verified on both GPUs |
| Status bar controls | DMS workspaces, tray, audio, networking, Bluetooth, power, clock | No duplicate status services |
| Agent indicator | Optional follow-up after identifying existing integration | Do not imply feature parity without implementing it |
| Five-minute automatic lock | Supported DMS lock/idle integration | Suspend, resume, failed unlock, and multi-monitor locking tested |
| Monitor and dock controls | niri output defaults plus per-device overrides and an accessible display UI | Dock/undock, mixed scaling, refresh rates, and lid behavior tested |
| Comfortable terminal | Ghostty with Nerd Font, clipboard shortcuts, and TUI-compatible Shift+Enter | Zed terminal, tmux, OpenCode, and remote SSH input tested |
| Quick system maintenance | Discoverable update, rollback, diagnostics, and snapshot actions | Privileged/destructive operations require human confirmation |
| Easy config recovery | Vendor defaults plus personal override files and explicit backup-before-reset | Update preserves edits, reset previews and requires confirmation |
| Staged update visibility | DMS bar indicator plus an explicit reboot action showing the staged version | The operator sees a pending update and chooses when to reboot |
| Suspend and resume reliability | NVIDIA suspend, resume, and hibernate hooks plus a tested power transition | Repeated suspend/resume cycles work with both monitors and a running game |
| Per-device power and display profiles | niri output includes and udev rules keyed to dock and monitor identity | Dock and undock restore scale, refresh rate, lid policy, and Ethernet |
| Audio state | WirePlumber per-device defaults, microphone noise suppression, and Bluetooth codec preference | Dock audio and call microphone switch correctly |
| Notification and clipboard discipline | Do-not-disturb, history, secret exclusion, clear on lock, and one notification daemon | Clipboard excludes password-manager entries and no duplicate daemons run |
| Offline recovery and diagnostics | Local recovery page, `bootc status`, rollback with confirmation, and a redacted diagnostics bundle | Recovery works from a TTY with no network |

Observed sources: ~/.config/omarchy/shell.json defines the current controls and a 300-second lock.
~/.config/ghostty/config includes clipboard bindings and CSI-u Shift+Enter handling.
Personal Hyprland bindings and autostart files currently contain examples rather than active customizations.
Do not carry the current tiny terminal font or monitor-specific settings to the laptop unconditionally.

### Role-focused QoL split

The image and the dotfiles repository each own a distinct part of the developer experience.
Do not install the same tool in both layers.

| Need | Image responsibility | Dotfiles responsibility | Acceptance check |
| --- | --- | --- | --- |
| Operations toolbelt | Rootless Podman, Distrobox, networking, and no host package layering | A pinned operations container with kubectl, Helm, OpenTofu, cloud CLIs, k9s, stern, and kubectx | Tools run from the container and the host image stays unchanged |
| Project runtimes | Base libraries only | The existing mise or devcontainer setup, project pin files, and direnv | A project pins its toolchain without a global install |
| Secrets and signing | No private keys or credentials in the image | Bitwarden SSH agent, age or sops, and a gitleaks pre-commit hook | No plaintext secret enters git and commits are signed |
| CI parity | The image workflow runs hadolint, shellcheck, trivy, and syft | Matching local pre-commit and `just` recipes | Local and CI checks agree |
| Junior onboarding | A TTY recovery path and a system diagnostics entry | A first-day checklist, project template, PR template, and break-glass runbook | A new user completes setup in one session |
| Learning aids | The offline recovery page | `tldr`, `cheat`, `/explain`, and labeled cheatsheets | Lookup works without network |
| Local cluster | Podman and the required kernel support | An optional kind or k3d helper with tested rootless limits | Cluster create and delete leave host state clean |
| Diagnostics | A redacted system bundle from `dux-diagnostics` | An issue template and the report path | A report contains no secrets |

The split rule is explicit:

- The image owns anything that needs root, the kernel, systemd, polkit, or boot.
- Dotfiles own anything user-scoped, project-pinned, or personal.
- A tool that needs both gets one image capability and one dotfiles recipe, never two installers.
- Operations tools stay out of the image to avoid version drift. The container recipe carries the versions.
- Junior defaults favor safe, reversible actions and visible failure. No passwordless sudo, broad mounts, or silent cleanup.

## Independent fallback desktop

Ship a minimal Xfce on X11 session alongside the default niri/DMS session.
The operator selects the session at login. Do not automatically change sessions after a failure.
Verify greetd/Dux Greeter session selection and the X11 launch path before committing to that login implementation.
Maintain a documented TTY recovery path if the graphical greeter fails.

Xfce owns its panel, window manager, settings, power handling, and lock screen inside its session.
DMS and niri-specific services must not start in Xfce.
Use session-specific portal selection and environment configuration.
Preserve common applications without installing an entire second application bundle.
Keep Xfce mostly stock, with separate mutable preferences.
Theme changes in DMS must not silently replace Xfce preferences.

The fallback addresses niri/DMS problems and offers a familiar conventional desktop.
It does not protect against shared kernel, NVIDIA, filesystem, or authentication failures.
OS rollback and TTY recovery remain separate requirements.

Validate Fedora 45 package availability, both session launch paths, lock/suspend behavior, application portals, and switching between sessions.
Test Xfce on both Intel and NVIDIA hardware.
X11 has weaker cross-application isolation than Wayland, so it is a compatibility fallback rather than the preferred security posture.

Sources: https://www.xfce.org/about/tour420 and https://fedoraproject.org/spins/xfce.
The Xfce 4.20 documentation describes its Wayland support as experimental.
Do not select experimental Xfce Wayland merely to avoid supporting an X11 fallback.

## AI development safety and usability

### Existing assistant

Preserve the existing dev-server assistant and fleet configuration.
Do not move services, expose a new listener, or rewrite its authentication as part of the image build.
Before connecting it, determine whether commands execute on the server, workstation, or container.
A remote interface does not imply remote execution.

### Safe local project workflow

Provide one discoverable launch action from Ghostty or the desktop menu.
It opens an approved project in a disposable rootless Podman environment with:

- Only the selected repository mounted writable, preferably a separate worktree.
- A separate home and explicitly scoped cache volumes.
- No host home, SSH directory, SSH agent, desktop-session sockets, Podman socket, or broad device mounts.
- No privileged mode, host namespaces, or host administrative access.
- SELinux enforcing, dropped unnecessary capabilities, and no-new-privileges where compatible.
- Explicit resource limits and visible container identity.
- Default network isolation. An explicit online profile permits network access for model APIs and dependencies.
- Only the credentials needed for that session, with documented scope and removal.

Online profiles cannot prevent exfiltration merely by running in a container.
Package managers and coding tools can execute arbitrary project code.
The workflow must label network and credential access honestly.

First use should require choosing a project and a profile, not memorizing Podman flags.
Sessions can be stopped, inspected, and recreated from a documented menu or short command.
Exact command names and runtime flags belong to implementation, after current documentation checks.

Distrobox remains available for trusted development convenience.
It is not the restricted agent runner because its host integration intentionally exposes user resources.

### Optional remote workstation access

Dedicated agent user, no sudo or wheel membership, no administrative polkit grants, and no access to the personal home.
Expose only deliberately shared project paths and project-specific permissions.
Tailscale grants/ACLs restrict which server identity can reach which workstation service.
Tailnet membership alone grants no workstation administration privileges.
SSH identity provisioning and ACL changes require explicit operator approval.
Never reuse or bake private keys or enrollment credentials.

No host SSH access is provisioned automatically during image build.
The local launcher and existing remote assistant can ship independently.

## Updates, signing, and NVIDIA

Build generic and NVIDIA images from the same verified Fedora 45 base digest.
Resolve exact tags and NVIDIA akmods installation instructions during implementation.
The NVIDIA module build must match the image kernel, including userspace and required 32-bit libraries.
Fail the build if versions disagree.

Use upstream's currently supported image-template approach, pinned dependencies, and documented licenses.
Zirconium remains a reference for desktop integration, not a copied configuration tree.

Build pull requests without publishing trusted stable releases.
Verify image contents, run bootc container lint, and boot a candidate in a VM.
Publish immutable candidate references with signatures and build provenance.
Only promote a hardware-approved candidate digest to the stable channel.
Do not rebuild a different image during promotion.
Both variants require their hardware acceptance records before their own promotion.

Hosts verify our signing identity through an installed containers policy and pinned trust configuration.
A valid signature establishes publisher identity, not correctness.
Test rejected unsigned and incorrectly signed images.
Private signing material stays in CI secrets, never the image or git.

Automatic updates stage only the stable channel.
Do not configure automatic reboot.
Rollback restores the previous OS deployment, not home contents, all application state, or every /etc change.
Document boot-menu recovery, a terminal rollback path, and retained known-good image digests.

Desktop Secure Boot is currently disabled.
The target is signed kernel/module compatibility where available.
Do not promise that container signing satisfies Secure Boot, or disable laptop Secure Boot to simplify a driver recipe.
Laptop Secure Boot state and employer requirements are deployment gates.

## Snapshots and data recovery

Provide btrbk as the proposed snapshot manager, subject to layout validation.
Snapshots are disabled until per-device paths, retention, and permission policy are configured explicitly.
Initial proposed retention: daily snapshots for seven days and weekly snapshots for four weeks.
An operator can request an additional pre-change snapshot.

Keep snapshots outside ordinary agent writable paths.
A privileged system unit owns snapshot creation and pruning.
Exclude snapshot storage from recursive backup and prevent recursive snapshot layouts.
Restore requires human confirmation and a documented preview.
Test recovery of a deleted file before relying on the feature.

Home snapshots may contain credentials and private work data.
They require the same access protection as the source home.
Same-disk snapshots do not protect against disk failure, theft, or privileged compromise.
External backup and verified restoration remain mandatory before the desktop wipe.
Existing encryption must be preserved or explicitly re-established during installation.

## Verification and release acceptance

Before implementation completion:

1. Static checks validate shell syntax, lint, build inputs, package manifests, and secret exclusion.
2. Both image variants build and pass bootc lint.
3. Tests reject kernel/module mismatch and invalid signatures.
4. Generic VM boots into Dux Greeter and a niri session.
5. Fresh-user setup installs applications and deploys dotfiles without conflicts.
6. Repeating setup converges without duplicate entries or overwriting edits.
7. An image upgrade preserves personal niri, Ghostty, Zed, and OpenCode configuration.
8. The safe agent runner can edit only the approved project and cannot access host secrets or management sockets.
9. Offline and online profiles expose their permissions accurately.
10. The workstation agent account cannot elevate or read the personal home.
11. Staging, reboot activation, and OS rollback work without an automatic reboot.
12. Snapshot creation and file restoration work on the real filesystem layout.

Hardware UAT:

- Desktop: NVIDIA driver loaded, both monitors, refresh rates, scaling, resume, Steam game, controller, audio, screen sharing.
- Laptop: internal/external displays, repeated dock/undock, charging, dock Ethernet/USB/audio, suspend/resume, lid behavior, Wi-Fi, Bluetooth, indie game.
- Both: Zed terminal/LSP, Ghostty/tmux/OpenCode input, tailnet connectivity, lock/unlock, Flatpak launch, secrets handling.

No monitor, dock, or NVIDIA success claim without recorded physical-machine evidence.
The operator performs UAT steps that require physical access.

## Implementation latitude and stop conditions

The builder chooses exact supported package names, Fedora repositories, application IDs, units, paths, and command names after live documentation checks.
The builder may choose a maintained alternative to a convenience tool if it preserves the workflow and ownership boundaries.
Record such choices and their evidence in implementation documentation.

Stop for operator approval if:

- Fedora 45 base-main is unavailable or the chosen base is retired.
- NVIDIA integration requires dropping security requirements or replacing the kernel unexpectedly.
- Work policy prohibits the custom laptop OS.
- Dotfiles integration would replace local-only configuration or broaden agent permissions.
- Ad-hoc package expectations cannot be met without changing the update model.
- Migration or snapshot configuration risks existing data.

Implementation planning must create forge work items before code changes once the GitHub repository exists.
Use feature branches and reviewed PRs, not direct main pushes.
Do not create a second shared backlog in this repository.

## Sources and evidence

Primary upstream sources inspected during discovery:

- https://github.com/ublue-os/main and its Containerfile, Justfile, packages.json, build_files/install.sh.
- https://github.com/ublue-os/image-template for supported custom image and NVIDIA approaches.
- https://duxlabs.dev/docs/getting-started and https://duxlabs.dev/docs/dms/installation.
- https://github.com/zirconium-dev/zirconium as a niri/DMS reference.

Local sources inspected:

- ../dotfiles/README.md: stages, ownership, configuration deployment, backup behavior.
- ../dotfiles/AGENTS.md: golden-tree, shell ownership, report-only system stage, and test rules.
- ../dotfiles/packages/system.txt: current Bazzite target and layered development packages.
- ../dotfiles/packages/Brewfile: current user CLI, GUI, and OpenCode ownership.
- ../dotfiles/install/30-settings.sh: conservative overlay and symlink deployment.
- ~/.config/omarchy/shell.json and ~/.config/ghostty/config: current ergonomics.
- Read-only lspci, DRM connector status, bootctl, findmnt, and laptop os-release discovery output.

Package availability and API details are validation inputs, not frozen promises from this design.
The implementation plan must verify current documentation before emitting operational commands.
