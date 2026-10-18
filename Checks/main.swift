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

enum SimulatedFailure: Error { case dispatch }
var iconExposed = false
do {
    try await restoringLayout(operation: {
        iconExposed = true
        throw SimulatedFailure.dispatch
    }, restore: { iconExposed = false })
    preconditionFailure("Input failure must remain observable")
} catch {}
precondition(!iconExposed, "An input failure must still restore the layout")
print("PASS: native input failure restores the exposed icon")

let freshFile = directory.appendingPathComponent("identity.json")
let identityStore = try LayoutStore(file: freshFile)
do {
    try identityStore.discover([ItemIdentity(id: "same", name: "One"), ItemIdentity(id: "same", name: "Two")])
    preconditionFailure("Competing identities must not silently select one icon")
} catch {}
precondition(identityStore.items.isEmpty, "Ambiguous input must not commit a guessed identity")
print("PASS: competing identities cannot inherit one another's configuration")
