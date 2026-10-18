# FoldBar

An intentionally minimal macOS menu bar manager: one downward arrow, a drawer for hidden icons, and persistent drag-and-drop ordering.

## Development status

Version 1.0 is being specified. This repository currently contains the confirmed workflow configuration and product decisions; there is no working application or installable release yet.

Specs and development tickets are tracked as local Markdown under `.scratch/` and versioned in this repository. Product terminology lives in `GLOSSARY.md`; accepted design decisions live in `docs/adr/`.

## Scope

- Show hidden menu bar icons in a drawer opened from a downward arrow.
- Detect menu bar icons and configure visibility and ordering by dragging.
- Keep configured relative order across application restarts.
- Synchronize visibility and ordering across desktops (Spaces) and external displays.
- Work when the system menu bar is revealed in fullscreen or auto-hide mode.
- Provide launch at login, necessary permission controls, and About inside Settings.
- Keep the arrow's context menu limited to Settings and Quit.
- Version 1.0; manual downloads only, with no automatic update checks.

The initial distribution targets Apple Silicon, prioritizing macOS 27 and newer versions. The planned deployment minimum is macOS 14; only systems actually tested will be listed as verified. Initial DMGs will be ad-hoc signed and unnotarized, with manual downloads through GitHub Releases.

FoldBar will deliberately persist only one `config.json` for icon ordering and visibility. Icon captures stay in memory. macOS manages login registration, permissions, and may create system preferences or diagnostic records; the uninstall instructions will distinguish these from FoldBar's own file.

## License and attribution

GPL-3.0. The implementation will reuse or adapt essential platform mechanisms from [Ice](https://github.com/jordanbaird/Ice), with source attribution and modification notices retained. No Ice application code has been incorporated at this stage.
