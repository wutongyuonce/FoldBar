import Foundation
import FoldBarCore

let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: directory) }
let file = directory.appendingPathComponent("config.json")
let layout = try LayoutStore(file: file)
try layout.discover([ItemIdentity(id: "alpha", name: "Alpha"), ItemIdentity(id: "beta", name: "Beta")])
let reopened = try LayoutStore(file: file)
precondition(reopened.items.map(\.id) == ["alpha", "beta"], "First discovery must survive restart in observed order")
try reopened.discover([ItemIdentity(id: "beta", name: "Beta"), ItemIdentity(id: "alpha", name: "Alpha"), ItemIdentity(id: "gamma", name: "Gamma")])
precondition(reopened.items.map(\.id) == ["alpha", "beta", "gamma"], "Launch order must not replace configured order")
print("PASS: discovery persists and new items append without changing existing order")
try reopened.move(id: "beta", to: .hidden, before: nil)
try reopened.move(id: "gamma", to: .visible, before: "alpha")
let restored = try LayoutStore(file: file)
try restored.discover([ItemIdentity(id: "beta", name: "Beta")])
precondition(restored.ordered(.visible).map(\.id) == ["gamma", "alpha"], "Offline icons must retain their manually chosen positions")
precondition(restored.ordered(.hidden).map(\.id) == ["beta"], "Visibility must survive restart")
print("PASS: manual grouping and order survive absence and restart")

let blocked = directory.appendingPathComponent("blocked")
try Data([0]).write(to: blocked)
let cannotSave = try LayoutStore(file: blocked.appendingPathComponent("config.json"))
do {
    try cannotSave.discover([ItemIdentity(id: "alpha", name: "Alpha")])
    preconditionFailure("A failed write must be reported")
} catch {
    precondition(cannotSave.items.isEmpty, "A failed write must not commit an in-memory layout")
}
let damaged = directory.appendingPathComponent("damaged.json")
try Data("{not json".utf8).write(to: damaged)
do { _ = try LayoutStore(file: damaged); preconditionFailure("Corrupt configuration must not be silently reset") } catch {}
let preserved = try Data(contentsOf: damaged)
precondition(preserved == Data("{not json".utf8), "Corrupt source must be preserved")
print("PASS: failed persistence rolls back and damaged data is preserved")

let freshFile = directory.appendingPathComponent("identity.json")
let identityStore = try LayoutStore(file: freshFile)
do {
    try identityStore.discover([ItemIdentity(id: "same", name: "One"), ItemIdentity(id: "same", name: "Two")])
    preconditionFailure("Competing identities must not silently select one icon")
} catch {}
precondition(identityStore.items.isEmpty, "Ambiguous input must not commit a guessed identity")
print("PASS: competing identities cannot inherit one another's configuration")

let slotFile = directory.appendingPathComponent("application-slots.json")
let slots = try LayoutStore(file: slotFile)
try slots.discover([ItemIdentity.discovered(bundleID: "com.example.Reader", name: "Reader", identifiers: ["content:1"], at: 0)!])
try slots.move(id: "com.example.Reader/app", to: .hidden, before: nil)
let newProcess = try LayoutStore(file: slotFile)
try newProcess.discover([ItemIdentity.discovered(bundleID: "com.example.Reader", name: "Reader — new content", identifiers: ["content:2"], at: 0)!])
precondition(newProcess.ordered(.hidden).map(\.id) == ["com.example.Reader/app"], "One app's slot must survive process and icon-content changes")
precondition(newProcess.items.count == 1, "A changing single app icon must not create another slot")
precondition(ItemIdentity.discovered(bundleID: "com.example.Multi", name: "Multi", identifiers: ["", ""], at: 0) == nil, "Simultaneous indistinguishable icons must not inherit an app slot")
precondition(ItemIdentity.discovered(bundleID: "com.example.Multi", name: "Multi", identifiers: ["one", "two"], at: 1)?.id == "com.example.Multi/ax:two", "Distinct simultaneous icons need separate records")
let multiInstance = ["", ""].enumerated().compactMap { index, _ in
    ItemIdentity.discovered(bundleID: "com.example.TwoProcesses", name: "Two processes", identifiers: ["", ""], at: index)
}
let independent = ItemIdentity.discovered(bundleID: "com.example.New", name: "New", identifiers: [""], at: 0)!
try newProcess.discover(multiInstance + [independent])
precondition(newProcess.items.map(\.id) == ["com.example.Reader/app", "com.example.New/app"], "Competing processes must not block unrelated discovery or inherit a saved slot")
print("PASS: application-slot visibility survives restart and changing icon content")

// A controlled OS boundary simulates native menu lifetime, not internal model calls.
@MainActor final class NativeFixture: NativeInteractionBoundary {
    enum Failure: Error { case dispatch }
    var states: [NativeInterfaceState]
    var failDispatch = false
    var cancelDuringDispatch = false
    var exposed = false
    var restoredAfterDismissal = false
    var accessibleAfterFailure = false
    init(_ states: [NativeInterfaceState]) { self.states = states }
    func expose() async throws { exposed = true }
    func dispatch() async throws {
        if failDispatch { throw Failure.dispatch }
        if cancelDuringDispatch { throw CancellationError() }
    }
    func observe() async throws -> NativeInterfaceState { states.isEmpty ? .open : states.removeFirst() }
    func wait() async throws {}
    func restore(canMove: Bool) async throws {
        exposed = false
        restoredAfterDismissal = canMove
        accessibleAfterFailure = !canMove
    }
}
let closedMenu = NativeFixture([.pending, .open, .closed])
try await runNativeInteraction(closedMenu)
let closedRestored = closedMenu.restoredAfterDismissal
precondition(closedRestored, "A dismissed menu must restore the configured layout")
let vanished = NativeFixture([.open, .disappeared])
try await runNativeInteraction(vanished)
let vanishedRestored = vanished.restoredAfterDismissal
precondition(vanishedRestored, "An exited app must not block layout recovery")
let dispatchFailure = NativeFixture([])
await MainActor.run { dispatchFailure.failDispatch = true }
do { try await runNativeInteraction(dispatchFailure); preconditionFailure("Dispatch must fail visibly") } catch {}
let failedAccessible = dispatchFailure.accessibleAfterFailure
precondition(failedAccessible, "Input failure must release hiding")
let cancelled = NativeFixture([])
await MainActor.run { cancelled.cancelDuringDispatch = true }
do { try await runNativeInteraction(cancelled); preconditionFailure("Cancellation must propagate") } catch {}
let cancelledAccessible = cancelled.accessibleAfterFailure
precondition(cancelledAccessible, "Cancellation must leave icons accessible")
let longMenu = NativeFixture([.open, .open])
do { try await runNativeInteraction(longMenu, observationLimit: 2); preconditionFailure("A stuck menu must time out visibly") } catch {}
let timedOutAccessible = longMenu.accessibleAfterFailure
precondition(timedOutAccessible, "Timeout must not move icons under an open menu")
print("PASS: native menu dismissal, disappearance, dispatch failure, cancellation and timeout")
