import Foundation
import SwiftData

/// A single plain-text snippet.
///
/// `name` is optional. When it is blank, `displayName` falls back to the first
/// non-empty line of `content`, which keeps quick capture fast.
@Model
final class Snippet {
    var id: UUID = UUID()
    var name: String = ""
    var content: String = ""
    var isHidden: Bool?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortIndex: Int = 0

    var group: SnippetGroup?

    init(
        name: String,
        content: String,
        group: SnippetGroup? = nil,
        createdAt: Date = .now,
        sortIndex: Int = 0,
        isHidden: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.content = content
        self.isHidden = isHidden
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.sortIndex = sortIndex
        self.group = group
    }
}

extension Snippet {
    static func ordered(_ lhs: Snippet, _ rhs: Snippet) -> Bool {
        if lhs.sortIndex != rhs.sortIndex {
            return lhs.sortIndex < rhs.sortIndex
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    var isSecret: Bool {
        isHidden == true
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if isSecret {
            return trimmed.isEmpty ? "Hidden Snippet" : trimmed
        }

        if !trimmed.isEmpty {
            return trimmed
        }

        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return firstLine.isEmpty ? "Untitled Snippet" : String(firstLine.prefix(48))
    }

    var previewText: String {
        isSecret ? "" : content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
