# Current implementation

FoldBar is independently implemented with AppKit, SwiftUI, Accessibility, ScreenCaptureKit and ServiceManagement. Ice is a product reference only. The implementation is a development candidate; passing core checks is not platform acceptance.

## Authorities

- `LayoutStore` owns discovery registration, group membership, order, validation and atomic JSON replacement. Settings commands pass through this interface. Runtime enumeration cannot replace existing durable relative order.
- `MenuBarPlatform` owns AX discovery and identity evidence across all running instances; `ItemIdentity.discovered` resolves that evidence into durable slots. The platform also owns coordinates, region capture, supported native actions, desktop gestures and result checking. It reads supported attributes/actions rather than assuming all apps expose them.
- `MenuInteraction` owns original menu/panel observations through AX menu notifications, expanded/selected/shown-menu state and newly appearing owner/host windows. `runNativeInteraction` owns the bounded expose/dispatch/observe/restore flow. Timeout and uncertainty release hiding and require explicit recovery rather than moving icons under an open interface.
- `AppDelegate` serializes layout reconciliation and controls the app's status items, drawer, event monitors and Space/display lifecycle. Failed layouts have a visible retry path; timer events do not create a backlog or continuously retry a known failing signature.
- `AppModel` presents these authorities and system permission/login state. Capture errors are per-item visible tooltips; snapshots are discarded on endpoint disappearance/replacement and desktop geometry changes.

## Identity limits

The user confirmed application-slot semantics for single-icon apps: a bundle ID identifies the slot whenever exactly one icon is discovered across the app’s running instances. A changing label, icon image or process does not replace that slot. Distinct app-supplied AXIdentifiers distinguish multiple items. Simultaneous items without distinguishable identifiers are protected instead of guessing. Runtime PID, coordinates and window IDs never enter persistent identity.

This intentionally remembers the application's slot rather than promising independent identity for alternating icons. It follows the user-confirmed scope; multiple indistinguishable icons remain a stated restriction.

## Layout and capture

The app can command-drag only a currently hit-testable real item. Posting events alone does not constitute success; fresh AX position is checked. The compact boundary status item may be expanded to request overflow after grouping, then the app checks whether requested hidden items ceased to be hit-testable and whether previously presented visible items remain accessible. A mismatch releases the boundary and surfaces an error. This overflow behavior is not a documented cross-app hiding API and requires actual-system validation.

Region captures use ScreenCaptureKit; macOS 26+ uses SCScreenshotConfiguration with no output URL. Overlapping native overflow placeholders and failed hit tests cannot be used as a screenshot of the original icon. A cache can only retain the same live hidden endpoint's last valid capture, never an absent or replaced endpoint.

macOS 27 uses the expanded-interface delegate/session for the app's drawer. Earlier versions use a target/action fallback. AX coordinates are preferred over local NSStatusItem button transforms because current-system observation showed host-rendered status items.

## Storage and ownership

The only maintained app-owned data file is `~/Library/Application Support/FoldBar/config.json`. Atomic saving can create short-lived staging files; no screenshot/log/history/updater database is maintained. AppKit and macOS may maintain preferences, registration, TCC and diagnostic artifacts independently. Invalid configuration is preserved and automatic layout stops.

## Validation status

The executable core checks cover persisted discovery/order, manually changed grouping/order, absence, damaged data, failed writes, competing identities, application-slot continuity across changing icon content and process restart, and native interaction success/failure/cancellation/disappearance/timeout via a controlled OS boundary.

The actual app has been launched on macOS 27.0.1. Settings, permission status, real AX item discovery, some ScreenCaptureKit icon images, and About 1.0 were observed. A real layout movement attempt failed; the app surfaced the error and released hiding. Subsequent fixes require renewed final-bundle testing. Multi-display hardware is unavailable. No statement in this report declares full 1.0 acceptance complete.
