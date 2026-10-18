# FoldBar

An intentionally minimal macOS menu bar manager: one downward arrow, a drawer for hidden icons, and persistent drag-and-drop ordering.

## Development status

Version 1.0 is being specified. This repository currently contains the confirmed workflow configuration and product decisions; there is no working application or installable release yet.

Specs and development tickets are tracked as local Markdown under `.scratch/` and versioned in this repository. Product terminology lives in `GLOSSARY.md`; accepted design decisions live in `docs/adr/`.

## Scope

- Show hidden menu bar icons in a drawer opened from a downward arrow.
- Detect menu bar icons and configure visibility and ordering by dragging.
- Keep configured relative order across application restarts.
- Provide launch at login, necessary permission controls, and About.
- Version 1.0; manual downloads only, with no automatic update checks.

## License and attribution

GPL-3.0. The implementation will reuse or adapt essential platform mechanisms from [Ice](https://github.com/jordanbaird/Ice), with source attribution and modification notices retained. No Ice application code has been incorporated at this stage.
