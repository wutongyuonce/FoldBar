import Foundation

/// Restoration is a user-visible obligation even when native dispatch throws.
public func restoringLayout(
    operation: () async throws -> Void,
    restore: () async throws -> Void
) async throws {
    do { try await operation() }
    catch {
        let operationError = error
        do { try await restore() }
        catch {
            throw NSError(domain: "FoldBar.Interaction", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "\(operationError.localizedDescription)；恢复布局也失败：\(error.localizedDescription)"
            ])
        }
        throw operationError
    }
    try await restore()
}
