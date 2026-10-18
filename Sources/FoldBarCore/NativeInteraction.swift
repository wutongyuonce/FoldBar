import Foundation

public enum NativeInterfaceState { case pending, open, closed, disappeared }

/// Implementations represent the OS boundary; consumers observe completion or failure.
@MainActor public protocol NativeInteractionBoundary {
    func expose() async throws
    func dispatch() async throws
    func observe() async throws -> NativeInterfaceState
    func wait() async throws
    func restore(canMove: Bool) async throws
}

@MainActor public func runNativeInteraction(_ boundary: NativeInteractionBoundary, observationLimit: Int = 600) async throws {
    do {
        try await boundary.expose()
        try Task.checkCancellation()
        try await boundary.dispatch()
        for _ in 0..<observationLimit {
            try Task.checkCancellation()
            switch try await boundary.observe() {
            case .closed, .disappeared:
                try await boundary.restore(canMove: true)
                return
            case .pending, .open:
                try await boundary.wait()
            }
        }
        throw NSError(domain: "FoldBar.Interaction", code: 2, userInfo: [NSLocalizedDescriptionKey: "原应用界面尚未关闭，已暂停隐藏以保持可访问；关闭后请重新检测布局"])
    } catch {
        let operationError = error
        do { try await boundary.restore(canMove: false) }
        catch {
            throw NSError(domain: "FoldBar.Interaction", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(operationError.localizedDescription)；恢复失败：\(error.localizedDescription)"])
        }
        throw operationError
    }
}
