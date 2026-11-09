# Theme tooling: November 2026 evidence audit

Cutoff: 2026-11-09. Researcher: OpenRouter anthropic/claude-sonnet-5.5.
This supplements the [initial QOL report](2026-11-09-omarchy-qol.md).

The research agent fetched live release metadata, tagged source, documentation, and site revisions.
Its observations are recorded below. The parent attempted to repeat the two latest-release API fetches, but both returned HTTP 403.
Version details below are therefore agent-observed evidence, not independently revalidated release metadata by the parent.
No runtime test or package installation was performed.

## Version baseline

| Component | Agent-observed release or revision at cutoff | Primary source |
| --- | --- | --- |
| Omarchy | v4.5.0, published 2026-11-05T05:36:53Z, release commit ac2690cd7be4f47e4a255f5e2e78d904d436b068 | https://github.com/omacom/omarchy/releases/tag/v4.5.0 |
| Omarchy announcement | Page says November 4, distinct from the UTC release publication date | https://omarchy.org/news/2026/11/omarchy-4-5/ |
| Omarchy default branch | quattro, HEAD cbd0029f dated 2026-11-08, diverged from release | https://github.com/omacom/omarchy/tree/cbd0029f |
| Published manual | Undated, site refresh d0abab4c dated 2026-11-08, drawing from Omarchy d9cc361c | https://github.com/omacom/omarchy-site/commit/d0abab4c |
| DMS | v2.1.2, published 2026-11-08T15:45:05Z, commit 43255a46ea01e9d0de1fe8ce9897c0d71566b2a8 | https://github.com/duxlabs-dev/dux-shell/releases/tag/v2.1.2 |
| DMS documentation | 2.1 released documentation, 2.2 explicitly unreleased | https://duxlabs.dev/docs/dms/custom-themes and https://duxlabs.dev/docs/2.2/dms/custom-themes |
| Aether | v4.32.0 published 2026-10-04, commit 29d07b1a | https://github.com/omacom/aether/releases/tag/v4.32.0 |
| Aether licence addition | MIT added on 2026-10-27 in 2943f7db, after latest release | https://github.com/omacom/aether/commit/2943f7db |

The agent compared the Omarchy theme-authoring, themes, and screenshot manual files between v4.5.0 and the published manual source revision.
Those files were byte-identical. A dictation page contained a post-release addition.
Do not describe the entire published manual as a stable-release manual.
The repository version file is unsuitable as a release identifier: the agent found an alpha string at both the release and default branch.

## Theme-manager conclusions grounded in the released source

### Omarchy coupling

The v4.5.0 theme manager invokes Omarchy shell, the wallpaper renderer, application helpers, and Hyprland reloads.
It filters terminal/editor configurations, Lua files, and symlinks for themes classified as repository-installed.
Its .git-based trust heuristic should not be copied.
Source: https://github.com/omacom/omarchy/blob/v4.5.0/bin/omarchy-theme-set.

Use palette data and the switching workflow as references rather than porting the manager wholesale.

### DMS switching and integration

The agent read DMS v2.1.2, not a floating master branch:

- Custom JSON themes are selected through currentThemeName and customThemeFile settings.
- Theme IPC offers light, dark, toggle, and getMode, not a named-theme selection operation.
- Settings and custom-theme files have reload watchers.
- The Ghostty template writes the dankcolors theme.
- Zed theme templates are present in source, despite incomplete application-theming documentation.
- Source selects a wallpaper colour seed only for dynamic mode, not custom mode. This is not a runtime result.

Primary sources:

- https://duxlabs.dev/docs/dms/custom-themes
- https://duxlabs.dev/docs/dms/keybinds-ipc
- https://github.com/duxlabs-dev/dux-shell/blob/43255a46ea01e9d0de1fe8ce9897c0d71566b2a8/quickshell/Common/Theme.qml
- https://github.com/duxlabs-dev/dux-shell/tree/43255a46ea01e9d0de1fe8ce9897c0d71566b2a8/quickshell/matugen

Recommendation: keep the thin palette adapter in dotfiles, with DMS generating application colours.
Treat Zed integration as source-backed but untested, not automatically working.
Preserve existing OpenCode settings. Do not infer an OpenCode adapter from another application's template.

Before implementing activation, verify config.d precedence and the settings UI's write-back behavior.
Do not let a persistent dotfiles override fight the DMS UI's selected theme.

### Aether

The source is https://github.com/omacom/aether, a Go/Svelte application built with Wails v2.
Main-branch documentation describes standalone outputs, but that documentation was not verified against the older release.
Sources:

- https://github.com/omacom/aether/blob/d302f534/docs/standalone.md
- https://github.com/omacom/aether/blob/d302f534/docs/installation.md
- https://github.com/omacom/aether/blob/d302f534/docs/blueprints.md

The agent found no demonstrated niri/DMS target or Fedora runtime validation.
It found Fedora library packages, but that does not prove the application runs or exports a compatible theme.
The latest release predates the observed licence addition, so do not bundle that release on the assumption its tree carries MIT.
Review the exact source revision and applicable licence before redistribution.

Recommendation: keep Aether optional and outside the initial image.
If investigated later, consume only validated palette output through the same importer.
Do not run its apply/reload hooks against the operator's actual home.

## Unresolved checks

- DMS config.d precedence and settings UI write-back.
- Whether Ghostty and Zed templates are enabled by default in the packaged release.
- Exact palette mapping and contrast preservation.
- Aether tagged-release capabilities, Fedora/niri execution, and asset licensing.
- Licences for imported wallpapers and community themes.
- Runtime theme switching and custom-palette behavior on the built image.

The separate Fedora 45/Xfce/greeter compatibility research is still pending.
These theme findings do not establish fallback-desktop compatibility.
