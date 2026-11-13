import Foundation
import SwiftData

/// A recursively nestable folder that owns snippets and child groups.
///
/// Deleting a group cascades to its children and snippets. Ordering is stored
/// explicitly in `sortIndex` so the sidebar and quick menu agree.
@Model
final class SnippetGroup {
    var id: UUID = UUID()
    var name: String = ""
    var iconName: String?
    var createdAt: Date = Date()
    var sortIndex: Int = 0

    var parent: SnippetGroup?

    @Relationship(deleteRule: .cascade, inverse: \SnippetGroup.parent)
    var children: [SnippetGroup] = []

    @Relationship(deleteRule: .cascade, inverse: \Snippet.group)
    var snippets: [Snippet] = []

    init(
        name: String,
        parent: SnippetGroup? = nil,
        createdAt: Date = .now,
        sortIndex: Int = 0,
        iconName: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.iconName = iconName
        self.createdAt = createdAt
        self.sortIndex = sortIndex
        self.parent = parent
    }
}

extension SnippetGroup {
    static func ordered(_ lhs: SnippetGroup, _ rhs: SnippetGroup) -> Bool {
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    var displayIconName: String {
        let trimmed = iconName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "folder" : trimmed
    }

    var orderedChildren: [SnippetGroup] {
        children.sorted(by: SnippetGroup.ordered)
    }

    var orderedSnippets: [Snippet] {
        snippets.sorted(by: Snippet.ordered)
    }

    var ancestry: [SnippetGroup] {
        var path: [SnippetGroup] = []
        var seen: Set<UUID> = []
        var current: SnippetGroup? = self

        while let group = current, seen.insert(group.id).inserted {
            path.append(group)
            current = group.parent
        }

        return path.reversed()
    }

    var depth: Int {
        max(ancestry.count - 1, 0)
    }

    var snippetCount: Int {
        snippets.count + children.reduce(0) { $0 + $1.snippetCount }
    }

    var groupCount: Int {
        children.count + children.reduce(0) { $0 + $1.groupCount }
    }

    func isDescendant(of other: SnippetGroup) -> Bool {
        var current = parent
        var seen: Set<UUID> = []

        while let group = current, seen.insert(group.id).inserted {
            if group.id == other.id {
                return true
            }
            current = group.parent
        }

        return false
    }
}
