# Omarchy personalisation and QOL: grounded research

Access date: 2026-11-09.
Research agent: OpenRouter, anthropic/claude-sonnet-5.5.
This report condenses the agent's primary-source findings. Proposals are not runtime-verified implementations.

## Conclusion

Adapt Omarchy's theme workflow, not its entire manager.
Use DMS as the single colour-generation owner and import validated Omarchy palette data into DMS custom-theme JSON.
Keep personal theme collections and preferences in the existing dotfiles repository.
Do not redistribute wallpapers without checking their individual licences.

## Source and version baseline

- The current manual is https://omarchy.org/manual/.
- https://learn.omacom.io/2/the-omarchy-manual identifies itself as the legacy Omarchy 3 manual.
- The old basecamp repository redirects to https://github.com/omacom/omarchy. Its default branch is quattro and its code licence is MIT. Source: https://api.github.com/repos/omacom/omarchy.
- The manual is refreshed from the default branch, so its contents need not match a stable-channel installation. Source: https://raw.githubusercontent.com/omacom/omarchy-site/master/README.md.
- The research agent found installed package version 4.0.6-1. Upstream announced 4.5 on November 5: https://omarchy.org/news/2026/11/omarchy-4-5/.
- Dux's default documentation tree is version 2.1. A 2.2 tree exists but was not compared fully. Source: https://duxlabs.dev/docs.

Do not treat every current-manual feature as present on this workstation.

## Theme manager findings

### Data and switching

Omarchy separates palettes, backgrounds, templates, and application-specific actions.
User themes live under ~/.config/omarchy/themes and built-ins under /usr/share/omarchy/themes.
The principal palette file is colors.toml. User templates can override bundled templates.
Source: https://omarchy.org/manual/making-your-own-theme/.

The current theme-set script serializes changes with a lock, stages a next theme, switches links, updates applications, and runs a theme-set hook.
It also calls Omarchy shell, notification helpers, Hyprland reloads, and numerous application helpers.
Source: https://raw.githubusercontent.com/omacom/omarchy/quattro/bin/omarchy-theme-set.

These dependencies make a direct port larger than a palette importer and DMS integration.

### Existing graphical theme builder

Omarchy documents Aether as a graphical theme builder.
This is relevant prior art, not yet an approved dependency or a verified portable tool.
Its source, supported export formats, dependencies, and licensing would need their own compatibility check before adoption.
Source: https://omarchy.org/manual/making-your-own-theme/.

### DMS integration

DMS supports JSON custom themes, optional light/dark variants, live editing, and theme registries.
Its colour roles include primary, surface, background, and outline.
These are not a one-to-one match for Omarchy's terminal-style palette.
An importer therefore needs explicit colour mapping and contrast tests.
Source: https://duxlabs.dev/docs/dms/custom-themes.

DMS generates application colours on theme and wallpaper changes through matugen.
The documentation covers Ghostty, GTK, Qt, and browser integrations including Zen CSS.
Application coverage and configuration paths must be checked against the pinned DMS release.
Do not claim complete Zed or OpenCode integration from this research alone.
Source: https://duxlabs.dev/docs/dms/application-themes.

DMS documents light/dark IPC and wallpaper controls. The inspected theme IPC commands do not establish a named-theme-selection API.
Use documented custom-theme configuration rather than inventing an IPC operation.
Source: https://duxlabs.dev/docs/dms/keybinds-ipc.

### Proposed integration

```text
Omarchy palette + licensed wallpaper assets
                 |
    strict data-only import and validation
                 |
       DMS custom-theme JSON
                 |
      DMS colour generation/templates
       |          |          |
    Ghostty     GTK/Qt     opted-in apps
```

- Use DMS's theme browser before building another picker.
- Support curated static themes and wallpaper-generated colours as separate modes.
- Keep local preferences in dotfiles, and generated outputs out of authoritative settings files.
- Back up affected user files and retain the previous selection.
- Distinguish import failure, successful palette activation, and partial application-refresh failure.
- Do not copy Omarchy's best-effort error handling as an unreported success path.
- Keep trusted local theme/font hooks optional. Downloaded themes cannot install hooks.

These are design recommendations, not features already built.

## Security and licensing

Omarchy filters executable or program-bearing configurations from themes installed through its repository workflow.
The source drops Lua and several terminal/editor configurations, and skips symlinks during installed-theme staging.
However, its classification of an installed theme uses .git presence. Do not copy that trust heuristic.
Sources:

- https://omarchy.org/manual/making-your-own-theme/
- https://raw.githubusercontent.com/omacom/omarchy/quattro/bin/omarchy-theme-set
- https://raw.githubusercontent.com/omacom/omarchy/quattro/bin/omarchy-theme-install

Ghostty warns that theme files can set arbitrary configuration options.
Never accept a downloaded Ghostty configuration as harmless colour data.
Source: https://ghostty.org/docs/config/reference.

Proposed importer: accept schema-validated palette fields and bounded, explicitly supported image files.
Reject executable templates, hooks, symlinks, path traversal, and arbitrary configuration files.
If archive downloads are used, validate extraction paths and resource limits before extraction.
Do not infer trust from transport, filenames, or a missing .git directory.

Omarchy's code licence is MIT. That does not establish the provenance of every bundled wallpaper.
The agent sampled eight community repositories and found several without a detected licence.
That sample is not evidence about the entire gallery.
Check each asset before redistribution and retain required notices.
Sources: https://api.github.com/repos/omacom/omarchy and https://omarchy.org/themes/.

## QOL mapping

| Omarchy feature | Proposed treatment | Primary evidence |
| --- | --- | --- |
| Coordinated themes | Adapt palettes, let DMS generate app colours | https://omarchy.org/manual/making-your-own-theme/ and https://duxlabs.dev/docs/dms/application-themes |
| Theme picker | Prefer DMS browser and registry | https://duxlabs.dev/docs/dms/custom-themes |
| Aether theme editor | Investigate portability only if graphical palette editing is wanted | https://omarchy.org/manual/making-your-own-theme/ |
| Wallpaper collections | Keep theme associations, verify assets and DMS mode interactions | https://omarchy.org/manual/backgrounds/ |
| Font switching | Use personal configuration, avoid broad search-and-replace scripts | https://omarchy.org/manual/fonts/ |
| Gaps, corners, opacity | Use niri and DMS settings rather than port Hyprland configuration | https://omarchy.org/news/2026/11/omarchy-4-5/ and https://duxlabs.dev/docs/dms/application-themes |
| Keybinding conventions | Adapt familiar shortcut groups and expose a cheatsheet | https://omarchy.org/manual/hotkeys/ and https://duxlabs.dev/docs/dms/keybinds-ipc |
| Screenshots | Prefer DMS capture, not Omasnap/Omarchy shell integration | https://omarchy.org/manual/screenshots-recording/ and https://duxlabs.dev/docs/dms/cli-screenshot |
| OCR | Consider DMS screenshot output into tesseract and clipboard | https://omarchy.org/manual/text-extraction-dictation/ and https://duxlabs.dev/docs/dms/cli-screenshot |
| Colour picker | Prefer DMS colour picker | https://duxlabs.dev/docs/dms/cli-color-picker |
| Screen recording | Select and test a supported recorder separately | https://omarchy.org/manual/screenshots-recording/ |
| Web apps | Optional, verify browser support rather than assume Zen supports Chromium app windows | https://omarchy.org/manual/web-apps/ |
| User hooks | Optional trusted local theme/font hooks only initially | https://omarchy.org/manual/dotfiles/ |
| Config recovery | Adapt preview/backup/reset workflow with human confirmation | https://omarchy.org/manual/common-tweaks/ |
| OS update scripts | Do not port pacman/migration/snapshot machinery into bootc | https://omarchy.org/manual/updates/ |
| Agents panel and dictation | Separate optional scope, not implied feature parity | https://omarchy.org/news/2026/11/omarchy-4-5/ |

## Verification gaps

- No DMS/niri installation was available for runtime tests.
- The proposed OCR pipeline is untested.
- Wallpaper switching while a static custom palette is active needs verification.
- Aether source and Fedora portability were not investigated.
- Theme registry implementation and bundled wallpaper licences were not audited.
- Broad claims about third-party plugin or theme safety require additional review.
- Several large docs were truncated. The agent reread key pages through text extraction but did not audit every linked project.
- One nonessential upstream themes/README.md URL returned 404.

## Pending choices

- Confirm the adapter approach rather than an exact Omarchy picker port.
- Choose initial palettes and default static versus wallpaper-generated mode.
- Decide whether graphical palette authoring through Aether is desired.
- Select a recorder and decide whether OCR/webapps belong in the initial release.
- Define how theme changes interact with the proposed independent fallback desktop.
