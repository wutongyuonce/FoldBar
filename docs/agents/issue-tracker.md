# Issue tracker: Local Markdown

Specs and tickets live in `.scratch/` and are versioned with the source.

- One feature per `.scratch/<feature-slug>/` directory.
- The spec is `spec.md` in that directory.
- Each ticket is `issues/<NN>-<slug>.md`, numbered in dependency order.
- Record `Status:` and `Blocked by:` near the top of each ticket.
- Use the triage role strings in `triage-labels.md`.
- Append discussion under `## Comments`.
- Publish to the tracker by writing the relevant local Markdown file.
- Fetch tickets by reading the referenced file. Ask if a number is ambiguous.

## Wayfinding

- The map is `.scratch/<effort>/map.md`; children are its numbered issue files.
- Record ticket type as research, prototype, grilling, or task.
- Wayfinder execution states are claimed and resolved, separate from triage roles.
- Claim the first open, unclaimed ticket whose blockers are all resolved.
- Resolve by recording the answer in the ticket and linking it from the map.
