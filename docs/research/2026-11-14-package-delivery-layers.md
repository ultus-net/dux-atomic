---
title: "Package delivery layers outside the image — research"
date: 2026-11-14
---

## Question and scope

For a tool the bootc image cannot or should not carry, what delivery methods should the operator consider, and how should this repository decide between them? Scope: Fedora bootc 45 base pinned by digest, no rpm-ostree runtime layering in normal operation (bootc-managed), the image ships no interactive user, rootless podman available. Each of those constraints is traced to a repo file in `## The constraint this repo adds`. Primary-source evidence only; prior art (Universal Blue) treated as prior art, not authority.

## What each layer is for, per its own project

1) rpm-ostree / image layering (Fedora / rpm-ostree docs)

> "Hybrid image/packaging via package layering. It is possible to dynamically add more packages onto the system that are not part of the commit composed on the server. These additional 'layered' packages are persistent across upgrades, rebases, and deploys ..."  
> Source: rpm-ostree administrator handbook — "Hybrid image/packaging via package layering".

URL: https://coreos.github.io/rpm-ostree/administrator-handbook/

Quote used above: "Hybrid image/packaging via package layering. It is possible to dynamically add more packages onto the system that are not part of the commit composed on the server." — rpm-ostree admin handbook.

2) bootc guidance (bootc project)

> "However, any local state mutations such as package layering, removals, or enabling e.g. `rpm-ostree initramfs --enable` will cause `bootc upgrade` to error out. Hence if you choose to use such features, then you will need to switch over to interacting with rpm-ostree going forward for updates."  
> Source: bootc documentation (Relationship with rpm-ostree / client side operations).

URL: https://bootc.dev/bootc/relationships.html

Quote used above: "any local state mutations such as package layering ... will cause `bootc upgrade` to error out." — bootc docs.

3) Homebrew on Linux (Homebrew project)

> "The Homebrew package manager may be used on Linux and Windows Subsystem for Linux (WSL) 2... Homebrew does not use any libraries provided by your host system, except glibc and gcc if they are new enough."  
> "Homebrew expects a working system C compiler and the standard Linux development tools."  
> Source: Homebrew Documentation — Homebrew on Linux (requirements and intent).

URL: https://docs.brew.sh/Homebrew-on-Linux

Quote used above: "The Homebrew package manager may be used on Linux ... Homebrew does not use any libraries provided by your host system, except glibc and gcc if they are new enough." — Homebrew docs.

4) Distrobox (project)

> "Use any Linux distribution inside your terminal... The created container will be tightly integrated with the host, allowing sharing of the HOME directory of the user, external storage, external USB devices and graphical apps (X11/Wayland), and audio."  
> "distrobox-export – export apps and services from the container to the host" (subcommands include export).  
> Security caveat from the project: "Isolation and sandboxing are not the main aims of the project ... The container will have complete access to your home, pen drive, and so on, so do not expect it to be highly sandboxed like a plain docker/podman container or a Flatpak."  
> Source: distrobox README.

URL: https://github.com/89luca89/distrobox

Quote used above: "The created container will be tightly integrated with the host, allowing sharing of the HOME directory ..." and "Isolation and sandboxing are not the main aims of the project." — distrobox README.

5) Toolbox / Toolbx (Fedora containers/toolbox)

> "Toolbx environments have seamless access to the user's home directory, the Wayland and X11 sockets, networking ... This is particularly useful on OSTree based operating systems like Fedora CoreOS and Silverblue. The intention of these systems is to discourage installation of software on the host, and instead install software as (or in) containers."  
> Source: containers/toolbox README.

URL: https://github.com/containers/toolbox

Quote used above: "Toolbx environments have seamless access to the user's home directory ... This is particularly useful on OSTree based operating systems like Fedora CoreOS and Silverblue." — toolbox README.

6) Flatpak / Flathub (Flatpak project)

> "Flatpak is a framework for distributing desktop applications across various Linux distributions... Flatpak’s only technical requirements are that applications follow a small number of Freedesktop standards... Flatpak is best suited for desktop applications... Rootless install; sandboxed applications."  
> Source: Flatpak documentation (Introduction).

URL: https://docs.flatpak.org/en/latest/introduction.html

Quote used above: "Flatpak is a framework for distributing desktop applications across various Linux distributions... Flatpak is best suited for desktop applications." — Flatpak docs.

7) Nix (Nix project and Determinate Systems installer guidance for OSTree)

> "Nix is a purely functional package manager. ... Atomic upgrades and rollbacks... Multiple versions: You can have multiple versions or variants of a package installed at the same time."  
> Sources: Nix manual.  
> For OSTree/immutable hosts, the installer's own feature list claims: "It supports SELinux and OSTree-based distributions without asking users to make compromises", and that "It uses planners to create appropriate install plans for complicated targets". The README presents planners and does not publish an OSTree-specific plan description; what an OSTree plan contains was not verified from this source.  
> Sources: Nix manual and DeterminateSystems/nix-installer README (Features, Planners).

URLs: https://nixos.org/manual/nix/stable/  and https://github.com/DeterminateSystems/nix-installer

Quote used above: "Nix is a purely functional package manager... Atomic upgrades and rollbacks." — Nix manual.  
Quote (OSTree support): "It supports SELinux and OSTree-based distributions without asking users to make compromises" — DeterminateSystems/nix-installer README, Features list.

8) Language package managers for end-user CLIs

- pipx (Python): "pipx installs and runs end-user Python applications in isolated environments. It fills the same role as macOS's brew, JavaScript's npx, and Linux's apt." — pipx docs.  
  URL: https://pipx.pypa.io/

- npm (Node): the npm `install` documentation documents global installs (`--global`) and explains the global prefix/bin layout; the docs do not claim global npm is a system package manager or provide OS-level signing/rollback.  
  URL: https://docs.npmjs.com/cli/v9/commands/npm-install

- cargo (Rust): "cargo install — Build and install a Rust binary" — describes that cargo installs binaries into a per-user install root (default $HOME/.cargo) and is intended for local installed binaries.  
  URL: https://doc.rust-lang.org/cargo/commands/cargo-install.html

- go (Go): the `go` documentation describes `go install` as the command to install or update packages to $GOBIN or GOPATH; it is a language toolchain feature not a system package manager.  
  URL: https://pkg.go.dev/cmd/go#hdr-Install_and_update_packages

Quotes used above: pipx: "pipx installs and runs end-user Python applications in isolated environments."  

9) Universal Blue prior art (ublue-os / Bluefin)

Prior art only, not authority. The Bluefin Administrator's Guide states the split directly:

> "Adding packages directly onto the host image is discouraged in Bluefin. The operating system is designed to remain pristine and reproducible as an OCI image managed by `bootc`."
> "Workloads should be isolated in containers (via Distrobox or Devcontainers), CLI tools installed via Homebrew, and graphical applications installed from Flathub."
> Its table pairs "Flatpak apps", "Homebrew CLI tools", and "Distrobox / Containers" against "Graphical desktop apps", "Host utilities", and "Developer runtimes" under the heading "Avoid Layering on Host".
> Update cadence claim: "The system checks for updates every six(6) hours. This includes system updates, flatpaks, pet containers, and homebrew."
> Source: Bluefin Administrator's Guide, sections "Local Layering" and "System Updates".

URL: https://docs.projectbluefin.io/administration/

The same page records the Secure Boot cost of shipping a signed NVIDIA module: "`ujust enroll-secure-boot-key` | Enroll the Nvidia driver & KMOD signing key for secure boot (password: \"universalblue\")". That is a per-machine enrollment against a project-held key, and it is the cost this repository's #72 decision has to weigh.

What the Bluefin repository README establishes, and nothing more: it describes Bluefin as "a cloud-native desktop operating system that reimagines the Linux desktop experience for modern computing environments" and links the documentation above. It says nothing about Homebrew, so this record cites the administrator guide for the split and does not attribute Homebrew mechanics to the README.

URL: https://github.com/ublue-os/bluefin

Where this prior art does not transfer: Bluefin is an rpm-ostree system, so its users can still run `rpm-ostree install` and `rpm-ostree reset` as an escape hatch, which its own page documents. This repository's base is bootc-managed, and a local mutation there makes `bootc upgrade` error out (section 2), so Bluefin's "discouraged but possible" layering is not available here at all.

## The constraint this repo adds

- Image base pinned by digest and built from `FROM quay.io/fedora/fedora-bootc:45@sha256:<digest>` (build manifest).  
  Quote: "The base is pinned in the `Containerfile` as `FROM quay.io/fedora/fedora-bootc:45@sha256:<digest>`." — docs/build.md.  
  URL: docs/build.md

- bootc-managed host: local rpm-ostree mutations will cause bootc upgrades to fail; therefore runtime layering is not a transparent update path for this repository's images.  
  Quote: "any local state mutations such as package layering ... will cause `bootc upgrade` to error out." — bootc docs (above).  
  URL: https://bootc.dev/bootc/relationships.html

- The image ships no interactive user and a small verified tool set; developer tools beyond the compiler are delivered out of image (docs/developer-tooling.md).  
  Quote: "The image serves a machine that is a sysadmin's first and a developer's second... The image ships what has to work on a broken machine and what needs root, and the user-space layers arrive later." — docs/developer-tooling.md.  
  URL: docs/developer-tooling.md

## Comparison

One row per layer, one line per row so the table renders. The evidence for each cell is in the section above and in `## Sources`.

| Layer | What it can carry | Pinning and rollback | Signature and trust | Update cadence | Failure mode | Operational cost |
| --- | --- | --- | --- | --- | --- | --- |
| Image (baked RPMs) | Full system packages, kernel, drivers, anything needing root or early boot (design spec: "The image owns anything that needs root, the kernel, systemd, polkit, or boot.") | Pin by `FROM` tag+digest plus NEVRA lock (docs/build.md); rollback is an image deployment rollback | Image signed, promotions attest provenance (design spec); the host policy must verify container signatures | Image rebuild and promotion, operator-controlled | Whole-OS rollback or reimage; users blocked until a rebuild lands | High: rebuild, publish, verify, hardware UAT |
| Homebrew (user or Linuxbrew) | CLI end-user tools, current language runtimes, bottles where published (docs: "Homebrew may be used on Linux ... does not use any libraries provided by your host system, except glibc and gcc") | A `Brewfile` pins formula names, not versions or digests; `brew switch`/`brew unlink` are ad hoc, with no system rollback | No OS-level signing; trust is Homebrew's bottles and Git history | Per Homebrew release, manual or timer-driven; Bluefin folds it into its six-hour check ("This includes system updates, flatpaks, pet containers, and homebrew.") | A broken formula breaks a user workflow, never boot; recover by reinstalling or removing the bundle | Medium: needs a runtime bootstrap and shell integration, and possibly a container |
| Distrobox or Toolbox (rootless container userland) | Any distribution's userland, full package managers inside, GUI apps exportable to the host (distrobox README: "tightly integrated with the host") | Pin the container image by digest; rollback is destroy and recreate from the previous digest | Registry and image signature trust; the host may not verify it | Per container image, independent of the host | Container or desktop integration breaks; the host stays bootable | Low to medium: rootless podman is already present; distrobox deliberately shares `$HOME` (its README: "Isolation and sandboxing are not the main aims of the project") |
| Flatpak or Flathub | Sandboxed GUI applications and shared runtimes (docs: "best suited for desktop applications") | Ref and branch per app; per-app rollback in some UIs, not system-wide | Its own repository and signature model; rootless and sandboxed | Per app and runtime, by its publisher | The app or a portal breaks; the system is unaffected | Low for GUI apps; consumes disk for runtimes |
| Nix | Declarative per-package builds, multiple versions co-installed, atomic profile rollback (manual: "Atomic upgrades and rollbacks") | Flake lockfiles and profile generations; rollback is a profile switch | Its own binary-cache signing and substitution trust, which is a separate operator decision | Per expression and cache update, independent of the distribution | Corrupt or misconfigured profiles break user tooling; the installer must place `/nix` correctly on an immutable host (README: "supports SELinux and OSTree-based distributions without asking users to make compromises", via planners) | Medium to high: a daemon, a store, and OSTree/SELinux care |
| Language package managers (`pipx`, `npm -g`, `cargo install`, `go install`) | Single-language CLIs, per user (pipx: "installs and runs end-user Python applications in isolated environments") | Ad hoc; no atomic upgrade and no rollback | Language registry publishing trust; no OS-level signature | Per ecosystem, usually frequent | One broken global install breaks one user tool; the host is unaffected | Low, with the weakest supply-chain guarantees here |
| Operations container (pinned podman image) | Cloud SDKs and CLIs (`kubectl`, `helm`, `terraform`), isolated from the host (docs/developer-tooling.md: "A pinned operations container, run with `podman`") | Pin by digest; rollback by running the previous digest; no host mutation | Registry and signature trust; a digest is an immutable reference | Independent of the OS, operator decides when to pull | Tooling breaks inside the container; the host is unaffected | Low on the host; needs image maintenance and a build job |

## Options for the operator (repo policies)

Option A — Image-first (conservative): put anything that needs root, kernel, or early-boot in the image; everything else in pinned operations containers or Flatpaks; use Homebrew only inside a container (distrobox) or as a user-level opt-in.  
  - Trades: maximal host reproducibility and verification; higher rebuild cost and slower updates for tools.  

Option B — Hybrid (current inherited split): keep compilers, core diagnostics, Podman and Distrobox in image; deliver convenience CLI via Homebrew (user-level Brewfile through dotfiles), GUI via Flathub, cloud CLIs in a pinned operations container.  
  - Trades: faster user updates and convenience; operational complexity: multiple update channels (brew, flathub, container images). (This is the repository's current split; see docs/developer-tooling.md.)  

Option C — Container-first (Toolbox/Distrobox default): image minimal, encourage Toolbox/Distrobox for developer tools and language runtimes, Flatpak for GUI; treat Homebrew and Nix as supported inside containers/toolboxes only.  
  - Trades: minimal image maintenance, clear separation of host vs user tools; requires user workflows and education for container use and app export.  

Option D — Nix-friendly: adopt Nix (Determinate) as the repository-supported user package manager, using the determinate installer's planners for an immutable host; allow Nix for per-user tooling and reproducible profiles.  
  - Trades: strong reproducibility and rollbacks for user tools, but significant operational cost, extra services, and ongoing maintenance on OSTree/bootc hosts.  

Recommendation (one-paragraph, labelled):

Recommendation: adopt Option B (Hybrid, the current split) but tighten its rules: require every user-level tool delivered via Homebrew or container to have an explicit source (Brewfile or pinned container digest), an automated verification smoke test in CI, and a documented recovery step; prefer containerized Homebrew (distrobox/toolbox) for initial bootstrap to avoid mixing host-level state with bootc-managed images.  

Rationale: it preserves the repository's current, tested workflows (dotfiles + Brewfile + pinned operations container + Flatpak for GUI), keeps the image small and verifiable, and recognises bootc's incompatibility with casual rpm-ostree layering. The extra verification (Brewfile, container digest pin, CI smoke) reduces the trust gap that Homebrew and language package managers introduce while keeping developer convenience high.

## What this record does not prove

- No source here was executed against this exact image build; "what works" on another Silverblue/bootc system may differ on this Fedora bootc 45 base.  
- No claim of supply-chain immunity: container/image signing, cosign bundles, and registry trust policies require separate implementation.  
- The repo has not tested Nix on this exact pinned base here; the installer README claims OSTree support and describes planners, but it does not publish what an OSTree plan does, so that behaviour is unverified here.  
- Homebrew, Distrobox, Toolbox, Flatpak, Nix, and the language package managers are described from their own documentation only. No page of theirs was run against this image, and no package was installed from any of them.  
- The Bluefin Administrator's Guide is cited as prior art for a split, not as evidence that the split works on this base. Its own layering escape hatch (`rpm-ostree install`) does not exist here.  

## Sources (primary)

- rpm-ostree administrator handbook — Hybrid image/packaging via package layering. https://coreos.github.io/rpm-ostree/administrator-handbook/
- bootc project — Relationship with rpm-ostree; client-side mutations cause `bootc upgrade` to error. https://bootc.dev/bootc/relationships.html
- Homebrew documentation — Homebrew on Linux (requirements, intent). https://docs.brew.sh/Homebrew-on-Linux
- Distrobox README — purpose, export, and security caveats. https://github.com/89luca89/distrobox
- Toolbx / Toolbox README — purpose for OSTree-based systems. https://github.com/containers/toolbox
- Flatpak docs — scope and runtime model. https://docs.flatpak.org/en/latest/introduction.html
- Nix manual — Nix features and atomic upgrades. https://nixos.org/manual/nix/stable/
- DeterminateSystems nix-installer README — planner model and the claim that OSTree-based distributions are supported; no OSTree plan detail published on that page. https://github.com/DeterminateSystems/nix-installer
- pipx docs — installing end-user Python CLIs. https://pipx.pypa.io/
- npm install docs — behavior of global installs; no OS-level signing/rollback in the doc. https://docs.npmjs.com/cli/v9/commands/npm-install
- cargo install docs — installing Rust binaries. https://doc.rust-lang.org/cargo/commands/cargo-install.html
- go install docs — go install and update packages. https://pkg.go.dev/cmd/go#hdr-Install_and_update_packages
- Bluefin Administrator's Guide — prior art for the split ("Local Layering"), its six-hour update check, and the per-machine NVIDIA key enrollment. https://docs.projectbluefin.io/administration/
- ublue-os/bluefin README — prior art only, for what the project says it is; the README does not describe Homebrew mechanics. https://github.com/ublue-os/bluefin
- repo files (local evidence): docs/developer-tooling.md, docs/build.md, docs/known-gaps.md, docs/superpowers/specs/2026-11-09-dux-atomic-design.md
