# FoldBar 1.0

Status: ready-for-agent

## Problem Statement

菜单栏图标不断增长，用户需要将较少使用的图标收到一个向下箭头下方，并用简单拖动决定显隐和顺序。应用启动顺序、退出重开、切换桌面或连接显示器都不应破坏已配置布局。现有工具包含大量本需求不需要的功能。

## Solution

提供一个原生 macOS 菜单栏应用。左键箭头展开隐藏组图标，右键菜单仅包含“设置”和“退出”。设置页包含显示组、隐藏组、开机启动、必要权限和 About。应用保存一份全局布局，在所有桌面和显示器上同步。提供 1.0 本地 DMG 与公开 GitHub 源码，用户通过 GitHub Releases 手动下载更新。

## User Stories

1. As a user, I want a downward arrow in the menu bar, so that the application occupies only one visible control.
2. As a user, I want to click the arrow to toggle the drawer, so that hidden icons remain easy to reach.
3. As a user, I want outside clicks and Escape to dismiss the drawer, so that it does not obstruct my work.
4. As a user, I want the arrow's context menu to contain only Settings and Quit, so that the application remains minimal.
5. As a user, I want hidden icons to retain their original left-click and right-click behavior, so that I can use the original application controls.
6. As a user, I want Settings to discover currently running menu bar icons automatically, so that I do not configure application identifiers manually.
7. As a user, I want separate visible and hidden groups in Settings, so that their meaning is clear.
8. As a user, I want to drag between groups, so that I can change visibility directly.
9. As a user, I want to drag within a group, so that I can determine its left-to-right order.
10. As a user, I want new icons appended to the visible group, so that existing choices stay intact.
11. As a user, I want simultaneously discovered icons registered in their current left-to-right order, so that the initial layout is predictable.
12. As a user, I want existing relative order to survive different application launch sequences, so that my layout stays stable.
13. As a user, I want missing applications to retain their configured slots, so that returning icons recover their previous positions.
14. As a user, I want absent icons shown as inactive in Settings, so that saved configuration is not confused with currently running applications.
15. As a user, I want layout synchronized across Spaces, so that switching desktops does not change my choices.
16. As a user, I want layout synchronized across external displays and connection changes, so that docking does not require reconfiguration.
17. As a user, I want FoldBar to work after revealing an automatically hidden menu bar, so that I can keep my normal macOS settings.
18. As a user, I want the arrow and drawer to work when the menu bar is revealed in a fullscreen application, so that fullscreen does not disable access.
19. As a user, I want system-restricted icons identified clearly, so that unavailable operations are not presented as successful.
20. As a user, I want ambiguous icon identities reported without guessing, so that one icon never inherits another icon's hidden state by accident.
21. As a user, I want permissions explained and requested from Settings, so that I can enable the required functionality deliberately.
22. As a user, I want my icons to remain accessible when permissions are missing or platform operations fail, so that FoldBar cannot strand them.
23. As a user, I want a launch-at-login switch reflecting the actual system registration, so that startup behavior is explicit.
24. As a user, I want About inside Settings with version 1.0 and the GitHub link, so that I can find source and downloads without extra menu entries.
25. As a user, I want manual downloads without automatic update traffic or notifications, so that the app stays quiet.
26. As a user, I want one application-owned persistent configuration file and memory-only screenshots, so that uninstalling is straightforward.
27. As a user, I want failed saves or invalid configuration surfaced without overwriting the last usable data, so that my layout is not silently lost.
28. As a user, I want quitting FoldBar to release its hiding mechanism, so that icons remain available without the app.
29. As a user, I want a local installable DMG and complete buildable source, so that I can install or rebuild the delivered version.
30. As a user, I want documented verification limits, so that I can distinguish implemented behavior from hardware and systems actually tested.

## Implementation Decisions

### Product and distribution

- Name: FoldBar; public repository: wutongyuonce/FoldBar; license: GPL-3.0. Independently implement the app using current Apple documentation, the macOS 27 SDK, and runtime evidence. Ice code and UI are reference material only; do not copy its implementation or treat its private API choices as authoritative.
- Native AppKit and SwiftUI application with a menu-bar-only lifecycle. About lives inside Settings; the arrow's context menu contains only Settings and Quit.
- Initial distribution targets Apple Silicon, prioritizing macOS 27 and newer releases. Minimum deployment target remains macOS 14, but compatibility is claimed only for tested versions. Future OS versions are not guaranteed merely because they are newer.
- Use the available Swift toolchain to build, assemble an app bundle, ad-hoc sign it, and produce a DMG. Initial delivery is unnotarized because no Developer ID certificate is available.
- GitHub Releases is the manual download page. There is no separate website, update service, telemetry, updater, or network activity initiated by the app except a user opening the GitHub/download links.
- Launch at login is initially disabled and uses the platform's supported registration service. The system is authoritative for its current state.

### Authorities and invariants

- The layout domain owns registered identities, membership, order, discovery rules, and configuration validation. Settings and the drawer present its results instead of independently deciding order.
- The platform adapter owns window discovery, identity evidence, display/Space association, system restrictions, screenshots, movement, input forwarding, and restoration. Prefer documented APIs; any necessary undocumented behavior is isolated and explicitly documented with observed limits inside this boundary.
- A single serial coordinator applies the authoritative layout to the live environment. Discovery and screen changes request reconciliation; they do not replace saved order with observed order.
- New identifiable icons append to the visible group. Initial simultaneous discovery is ordered left to right. Registered icons retain their relative order regardless of absence, restart, window identifiers, or display changes.
- Persistent layout edits originate from Settings drag operations. Transient changes in the system menu bar do not become new persisted order automatically.
- One logical icon has one saved record even if macOS exposes multiple display or Space representations. Runtime window IDs, process IDs, display IDs, and coordinates are not persistent identity.
- Single-icon apps (counted across all running instances) persist an application slot identified by their bundle ID. Icon content changes and process restarts inherit that slot. Distinct AXIdentifiers can identify multiple items from an app. This application-slot interpretation was explicitly confirmed by the user.
- Use stable identity evidence where available. If identity cannot be established without guessing between competing icons, present the ambiguity and keep the affected icon accessible; never silently transfer another icon's visibility or position.
- System-restricted icons remain visible with an explanation of their unavailable operations. Their system-mandated placement is excluded from the user-configured ordering guarantee.

### Interaction and synchronization

- Settings presents visible and hidden groups in left-to-right order, with drag-to-reorder and drag-between-groups. Offline records retain position and appear inactive.
- The drawer displays captured representations of hidden icons. Clicking transfers the original input semantics to the corresponding real icon; it does not merely launch the owning application.
- The independently implemented platform adapter may temporarily expose a real icon in the menu bar to interact with it, if current-system testing shows this is necessary. Restore the configured layout after its menu/panel is dismissed. Restoration must also run after failure or cancellation; disappearance of the owning application must not block recovery of the remaining layout.
- Do not move icons underneath an ongoing user drag or while a native icon interface is being used. Reconcile after that interaction ends.
- All Spaces and displays share one configuration. Space switches, display connection/disconnection, application lifecycle changes, wake, and permission changes invalidate transient geometry and trigger fresh discovery.
- Anchor the drawer to the screen on which the user activates the arrow, including when that screen has negative desktop coordinates or a different scale. Keep the drawer within usable screen bounds and allow overflow to be accessed without adding a second product feature.
- Automatically hidden menu bars and fullscreen applications are required scenarios: once the system menu bar is revealed, FoldBar must remain usable. Do not alter global macOS menu bar or Spaces preferences.
- Dismissal is by the arrow, outside click, or Escape. Empty hidden groups show a minimal empty state.

### Persistence, failure semantics, and resource bounds

- Deliberately persist only one configuration JSON containing schema version, registered icon identity/display metadata, and ordered visible/hidden membership. Capture images stay in memory; no screenshot cache, analytics store, log files, or updater files.
- A configuration change is successful only after a valid replacement is saved. Use atomic replacement; temporary write staging is cleaned up and is not another maintained data file.
- A failed save preserves the previous committed configuration and reports the error. Invalid, unreadable, duplicate, or unknown-version configuration is not silently reset or overwritten; enter a visible safe state with recovery guidance.
- Missing/revoked permissions, failed capture, identity ambiguity, or movement failure must be observable. Release hiding when continuing would make icons inaccessible; retain the user's saved configuration for later recovery.
- On normal quit, cancel active work, release the hiding controls, and remove event monitors. Losing the app's hiding windows on process termination must not leave a separate daemon controlling icons.
- Maintain at most one layout reconciliation or native movement interaction at a time. Coalesce incoming refresh requests instead of enqueueing an unbounded backlog.
- Movement attempts and event waits have explicit finite limits owned by the platform adapter. Exceeding a limit produces a visible failure and safe recovery, not infinite retries or a polling loop that consumes a CPU core.
- Bound discovery/capture work to the current menu bar item set; discard obsolete runtime window snapshots and screenshots after changes. Persist offline identity records because preserving their configured position is required.
- macOS-owned preferences, permission records, login registration, and diagnostic files are outside the one-file application guarantee. Document their ownership and applicable uninstall steps rather than promising zero OS artifacts.

## Testing Decisions

The user confirmed the following public test boundaries and the review baseline on 2026-10-18.

1. Layout commands: discover icons, drag between/within groups, and reopen the saved layout. Verify user-visible membership/order, absent and returning icons, identity ambiguity, and failed or invalid persistence through these interfaces, without asserting private collection structure.
2. Platform interaction operations: verify temporary exposure, input dispatch, and restoration after success, failure, cancellation, or disappearance through observable system-boundary outcomes. A controlled OS boundary may simulate failures; it does not establish real macOS compatibility.
3. Real application acceptance: permissions, icon detection, drag ordering, screenshots, original icon menus, startup registration, quitting, Space switches, external monitor changes, hidden-menu-bar/fullscreen interaction, and DMG installation. Report only scenarios actually exercised as passed.

- There is no existing test suite. Use small runnable Swift checks at the agreed boundaries without adding a third-party test framework.
- Each implementation slice follows red → green: first run a failing behavioral check, then implement the minimum necessary to pass it. Expected outcomes come from worked examples, not a duplicate of the implementation algorithm.
- Compile/typecheck regularly and run focused checks per slice. Run the full set once before delivery, then repeat only where fixes or unresolved concerns warrant it.
- Review both code standards and spec fidelity against initial configuration commit `2015783e6685eb53a060bb86668b1ad867c1f669`, using separate reviewer agents as required by code-review. Resolve substantive findings and keep current design, implementation, and tests aligned.
- Current build feasibility evidence is limited to successful AppKit/SwiftUI/ServiceManagement compilation, linkage of required system functions, and runtime symbol lookup on macOS 27.0.1. This is not evidence of functional icon control.
- Current hardware inventory contains only one built-in display. External-monitor acceptance requires connected hardware and must remain explicitly unverified until exercised.

## Out of Scope

- Themes, menu bar styling, search, hotkeys, schedules, profiles, per-display layouts, icon spacing controls, always-hidden third groups, widgets, telemetry, and automatic update checks or notifications.
- Overriding system restrictions or guaranteeing stable identity for indistinguishable third-party icons.
- An Intel package, App Store distribution, a separate download website, Developer ID signing, or notarization for this initial delivery.
- Claiming all past or future macOS releases are supported without testing.
- Removing arbitrary macOS-owned artifacts or altering system security settings automatically.

## Further Notes

Accepted behavior is recorded in the conversation and the domain decisions. This specification describes the intended final product, not completed functionality. Implementation tickets are published only after the user approves the proposed breakdown. Verification gaps must remain visible in the final delivery report; a passing build or simulated interaction cannot close a missing hardware acceptance check.
