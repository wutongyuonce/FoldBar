import Foundation

public enum ItemGroup: String, Codable, CaseIterable { case visible, hidden }

public struct ItemIdentity: Codable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var group: ItemGroup

    public init(id: String, name: String, group: ItemGroup = .visible) {
        self.id = id
        self.name = name
        self.group = group
    }

    public static func discovered(bundleID: String, name: String, identifiers: [String], at index: Int) -> ItemIdentity? {
        guard identifiers.indices.contains(index) else { return nil }
        if identifiers.count == 1 { return ItemIdentity(id: bundleID + "/app", name: name) }
        let identifier = identifiers[index]
        guard !identifier.isEmpty, identifiers.filter({ $0 == identifier }).count == 1 else { return nil }
        return ItemIdentity(id: bundleID + "/ax:" + identifier, name: name)
    }
}

public final class LayoutStore {
    private struct Document: Codable {
        var version = 1
        var items: [ItemIdentity]
    }

    public private(set) var items: [ItemIdentity]
    public let file: URL

    public init(file: URL) throws {
        self.file = file
        if FileManager.default.fileExists(atPath: file.path) {
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: file))
            guard document.version == 1,
                  Set(document.items.map(\.id)).count == document.items.count,
                  document.items.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            items = document.items
        } else {
            items = []
        }
    }

    public func discover(_ identities: [ItemIdentity]) throws {
        guard Set(identities.map(\.id)).count == identities.count,
              identities.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var candidate = items
        for item in identities where !candidate.contains(where: { $0.id == item.id }) {
            candidate.append(ItemIdentity(id: item.id, name: item.name))
        }
        if candidate != items { try commit(candidate) }
    }

    public func ordered(_ group: ItemGroup) -> [ItemIdentity] {
        items.filter { $0.group == group }
    }

    public func move(id: String, to group: ItemGroup, before target: String?) throws {
        guard id != target, let index = items.firstIndex(where: { $0.id == id }) else { return }
        var candidate = items
        var item = candidate.remove(at: index)
        item.group = group
        if let target {
            guard let destination = candidate.firstIndex(where: { $0.id == target && $0.group == group }) else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            candidate.insert(item, at: destination)
        } else {
            candidate.append(item)
        }
        try commit(candidate)
    }

    private func commit(_ candidate: [ItemIdentity]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(items: candidate))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic])
        items = candidate
    }
}
