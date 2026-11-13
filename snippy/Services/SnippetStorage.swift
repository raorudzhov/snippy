//
//  SnippetStorage.swift
//  snippy
//

import Foundation
import OSLog
import SwiftData

/// Shared loggers. Keeping categories separate makes Console.app useful when
/// debugging the store, paste path or global hot key.
enum AppLog {
    static let storage = Logger(subsystem: "raorudzhov.snippy", category: "storage")
    static let settings = Logger(subsystem: "raorudzhov.snippy", category: "settings")
    static let paste = Logger(subsystem: "raorudzhov.snippy", category: "paste")
    static let hotKey = Logger(subsystem: "raorudzhov.snippy", category: "hotkey")
}

/// The app-wide SwiftData container.
///
/// The store lives in Application Support inside the sandbox container. A
/// missing database is a fatal error: silently falling back to an in-memory
/// store would make the app look functional while losing every snippet.
@MainActor
enum SnippetStorage {
    static let container: ModelContainer = {
        let schema = Schema([
            SnippetGroup.self,
            Snippet.self
        ])

        do {
            let applicationSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = applicationSupport.appending(path: "Snippy", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            #if DEBUG
            let storeName = CommandLine.arguments.contains("--demo") ? "Demo.store" : "Snippets.store"
            #else
            let storeName = "Snippets.store"
            #endif

            let configuration = ModelConfiguration(
                schema: schema,
                url: directory.appending(path: storeName)
            )

            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A snippet manager without its local database is not useful, and silently
            // falling back to memory would hide the underlying problem from the user.
            fatalError("Could not create the Snippets data store: \(error)")
        }
    }()
}

/// Where an item should be placed relative to another item.
enum RelativePosition {
    case before
    case after
}

/// Small, explicit CRUD and ordering operations over `SnippetStorage`'s context.
///
/// All moves are committed as one save and renumber the affected sibling lists,
/// so `sortIndex` stays deterministic across launches.
@MainActor
enum SnippetStore {
    // MARK: - Reading

    static func rootGroups(from groups: [SnippetGroup]) -> [SnippetGroup] {
        groups
            .filter { $0.parent == nil }
            .sorted(by: SnippetGroup.ordered)
    }

    static func orderedGroups(of parent: SnippetGroup?, in context: ModelContext) -> [SnippetGroup] {
        if let parent {
            return parent.children.sorted(by: SnippetGroup.ordered)
        }

        let all = (try? context.fetch(FetchDescriptor<SnippetGroup>())) ?? []
        return all
            .filter { $0.parent == nil }
            .sorted(by: SnippetGroup.ordered)
    }

    static func orderedSnippets(of group: SnippetGroup?) -> [Snippet] {
        (group?.snippets ?? []).sorted(by: Snippet.ordered)
    }

    // MARK: - Creating

    @discardableResult
    static func createGroup(
        in context: ModelContext,
        name: String,
        parent: SnippetGroup?
    ) -> SnippetGroup {
        let siblings = orderedGroups(of: parent, in: context)
        let nextIndex = (siblings.map(\.sortIndex).max() ?? -1) + 1

        let group = SnippetGroup(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            sortIndex: nextIndex
        )
        context.insert(group)
        group.parent = parent
        save(context)
        return group
    }

    @discardableResult
    static func createSnippet(
        in context: ModelContext,
        name: String,
        content: String,
        group: SnippetGroup,
        isHidden: Bool = false
    ) -> Snippet {
        let nextIndex = (group.snippets.map(\.sortIndex).max() ?? -1) + 1

        let snippet = Snippet(
            name: resolvedName(name, content: content),
            content: content,
            sortIndex: nextIndex,
            isHidden: isHidden
        )
        context.insert(snippet)
        snippet.group = group
        save(context)
        return snippet
    }

    // MARK: - Updating

    static func update(
        _ snippet: Snippet,
        name: String,
        content: String,
        isHidden: Bool? = nil,
        in context: ModelContext
    ) {
        snippet.name = resolvedName(name, content: content)
        snippet.content = content
        if let isHidden {
            snippet.isHidden = isHidden
        }
        snippet.updatedAt = .now
        save(context)
    }

    static func rename(_ group: SnippetGroup, to name: String, in context: ModelContext) {
        group.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save(context)
    }

    static func updateIcon(_ group: SnippetGroup, to symbolName: String, in context: ModelContext) {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        group.iconName = trimmed.isEmpty ? nil : trimmed
        save(context)
    }

    // MARK: - Moving groups

    /// Moves a group to the end of another group's children, or to the root.
    @discardableResult
    static func moveGroup(
        _ group: SnippetGroup,
        into parent: SnippetGroup?,
        in context: ModelContext
    ) -> Bool {
        if let parent {
            guard parent.id != group.id, !parent.isDescendant(of: group) else {
                return false
            }
        }

        let oldParent = group.parent
        var destination = orderedGroups(of: parent, in: context)
            .filter { $0.id != group.id }
        destination.append(group)

        let oldSiblings = renumberableOldSiblings(
            of: group,
            oldParent: oldParent,
            newParent: parent,
            in: context
        )

        detach(group, from: oldParent, to: parent)
        renumber(destination)
        renumber(oldSiblings)
        save(context)
        return true
    }

    /// Moves a group before or after another group, staying at that group's level.
    @discardableResult
    static func moveGroup(
        _ group: SnippetGroup,
        near target: SnippetGroup,
        position: RelativePosition,
        in context: ModelContext
    ) -> Bool {
        guard target.id != group.id else { return false }

        let destinationParent = target.parent
        if let destinationParent {
            guard destinationParent.id != group.id,
                  !destinationParent.isDescendant(of: group) else {
                return false
            }
        }

        var destination = orderedGroups(of: destinationParent, in: context)
            .filter { $0.id != group.id }

        guard let targetIndex = destination.firstIndex(where: { $0.id == target.id }) else {
            return false
        }

        let insertionIndex = position == .before ? targetIndex : targetIndex + 1
        destination.insert(group, at: min(max(insertionIndex, 0), destination.count))

        let oldParent = group.parent
        let oldSiblings = renumberableOldSiblings(
            of: group,
            oldParent: oldParent,
            newParent: destinationParent,
            in: context
        )

        detach(group, from: oldParent, to: destinationParent)
        renumber(destination)
        renumber(oldSiblings)
        save(context)
        return true
    }

    // MARK: - Moving snippets

    /// Moves a snippet to the end of another group's snippets.
    @discardableResult
    static func moveSnippet(
        _ snippet: Snippet,
        into group: SnippetGroup,
        in context: ModelContext
    ) -> Bool {
        let oldGroup = snippet.group
        var destination = orderedSnippets(of: group)
            .filter { $0.id != snippet.id }
        destination.append(snippet)

        let oldSiblings = renumberableOldSnippets(
            of: snippet,
            oldGroup: oldGroup,
            newGroup: group
        )

        detach(snippet, from: oldGroup, to: group)
        renumber(destination)
        renumber(oldSiblings)
        save(context)
        return true
    }

    /// Moves a snippet before or after another snippet in the same group.
    @discardableResult
    static func moveSnippet(
        _ snippet: Snippet,
        near target: Snippet,
        position: RelativePosition,
        in context: ModelContext
    ) -> Bool {
        guard target.id != snippet.id,
              let destinationGroup = target.group else {
            return false
        }

        var destination = orderedSnippets(of: destinationGroup)
            .filter { $0.id != snippet.id }

        guard let targetIndex = destination.firstIndex(where: { $0.id == target.id }) else {
            return false
        }

        let insertionIndex = position == .before ? targetIndex : targetIndex + 1
        destination.insert(snippet, at: min(max(insertionIndex, 0), destination.count))

        let oldGroup = snippet.group
        let oldSiblings = renumberableOldSnippets(
            of: snippet,
            oldGroup: oldGroup,
            newGroup: destinationGroup
        )

        detach(snippet, from: oldGroup, to: destinationGroup)
        renumber(destination)
        renumber(oldSiblings)
        save(context)
        return true
    }

    // MARK: - Deleting

    static func delete(_ group: SnippetGroup, in context: ModelContext) {
        // SwiftData's cascade removes the model, but the in-memory inverse
        // collection can keep a tombstone until the next fetch. Updating it
        // here keeps the sidebar and detail lists immediately consistent.
        group.parent?.children.removeAll { $0.id == group.id }
        context.delete(group)
        save(context)
    }

    static func delete(_ snippet: Snippet, in context: ModelContext) {
        snippet.group?.snippets.removeAll { $0.id == snippet.id }
        context.delete(snippet)
        save(context)
    }

    // MARK: - Persistence

    static func save(_ context: ModelContext) {
        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            AppLog.storage.error("Failed to save snippets: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// A snippet can be created without a title. In that case the first non-empty
    /// line becomes its name, which keeps quick capture fast.
    static func resolvedName(_ rawName: String, content: String) -> String {
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""

        guard !firstLine.isEmpty else { return "Untitled Snippet" }

        if firstLine.count <= 52 {
            return firstLine
        }

        return String(firstLine.prefix(52)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Relationship helpers

    private static func detach(
        _ group: SnippetGroup,
        from oldParent: SnippetGroup?,
        to newParent: SnippetGroup?
    ) {
        oldParent?.children.removeAll { $0.id == group.id }
        group.parent = newParent

        if let newParent, !newParent.children.contains(where: { $0.id == group.id }) {
            newParent.children.append(group)
        }
    }

    private static func detach(
        _ snippet: Snippet,
        from oldGroup: SnippetGroup?,
        to newGroup: SnippetGroup
    ) {
        oldGroup?.snippets.removeAll { $0.id == snippet.id }
        snippet.group = newGroup

        if !newGroup.snippets.contains(where: { $0.id == snippet.id }) {
            newGroup.snippets.append(snippet)
        }
    }

    private static func renumberableOldSiblings(
        of group: SnippetGroup,
        oldParent: SnippetGroup?,
        newParent: SnippetGroup?,
        in context: ModelContext
    ) -> [SnippetGroup] {
        guard oldParent?.id != newParent?.id else { return [] }

        return orderedGroups(of: oldParent, in: context)
            .filter { $0.id != group.id }
    }

    private static func renumberableOldSnippets(
        of snippet: Snippet,
        oldGroup: SnippetGroup?,
        newGroup: SnippetGroup
    ) -> [Snippet] {
        guard oldGroup?.id != newGroup.id else { return [] }

        return orderedSnippets(of: oldGroup)
            .filter { $0.id != snippet.id }
    }

    private static func renumber(_ groups: [SnippetGroup]) {
        for (index, group) in groups.enumerated() {
            group.sortIndex = index
        }
    }

    private static func renumber(_ snippets: [Snippet]) {
        for (index, snippet) in snippets.enumerated() {
            snippet.sortIndex = index
        }
    }
}
