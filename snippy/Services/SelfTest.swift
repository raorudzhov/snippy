//
//  SelfTest.swift
//  snippy
//

#if DEBUG
import Foundation
import SwiftData

/// Development-only sanity checks for the recursive SwiftData model.
/// Run the debug build with `--self-test` to verify relationships and cascade
/// deletion without touching the user's snippet store.
@MainActor
enum SelfTest {
    private static var failures: [String] = []

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--self-test") else { return false }

        failures = []
        do {
            try run()
        } catch {
            failures.append("unexpected error: \(error)")
        }

        if failures.isEmpty {
            write("SELF-TEST PASSED")
            exit(0)
        } else {
            write("SELF-TEST FAILED")
            for failure in failures {
                write("  ✗ \(failure)")
            }
            exit(1)
        }
    }

    private static func run() throws {
        let schema = Schema([SnippetGroup.self, Snippet.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        // A small tree: Work > Email > Signatures.
        let work = SnippetStore.createGroup(in: context, name: "Work", parent: nil)
        let email = SnippetStore.createGroup(in: context, name: "Email", parent: work)
        let signatures = SnippetStore.createGroup(in: context, name: "Signatures", parent: email)
        let greeting = SnippetStore.createSnippet(
            in: context,
            name: "Greeting",
            content: "Best regards,\nAlex",
            group: signatures
        )
        let reply = SnippetStore.createSnippet(
            in: context,
            name: "",
            content: "Thanks for the quick reply.\n\nAlex",
            group: email
        )
        _ = SnippetStore.createSnippet(
            in: context,
            name: "Meeting notes",
            content: "Decisions",
            group: work
        )

        check(work.children.count == 1, "Work should contain one child group")
        check(email.parent?.id == work.id, "Email should have Work as its parent")
        check(email.children.first?.id == signatures.id, "Email should contain Signatures")
        check(signatures.parent?.id == email.id, "Signatures should have Email as its parent")
        check(signatures.ancestry.map(\.name) == ["Work", "Email", "Signatures"], "ancestry should be ordered")
        check(signatures.depth == 2, "Signatures should be at depth 2")
        check(work.snippetCount == 3, "Work should count nested snippets")
        check(work.groupCount == 2, "Work should count nested groups")
        check(signatures.isDescendant(of: work), "Signatures should be a descendant of Work")
        check(!work.isDescendant(of: signatures), "Work should not be a descendant of Signatures")
        check(signatures.snippets.count == 1, "Signatures should contain one snippet")
        check(greeting.group?.id == signatures.id, "Snippet should point at its group")
        check(reply.displayName == "Thanks for the quick reply.", "Blank names should use the first content line")
        check(SnippetStore.resolvedName("", content: "  \n\n  A line of text  \n") == "A line of text", "Auto names should trim")
        check(rootGroups(in: context).map(\.name) == ["Work"], "Work should be the only root group")

        // Deep nesting should remain fully usable.
        var parent = work
        var deepChain: [SnippetGroup] = []
        for index in 0..<40 {
            let child = SnippetStore.createGroup(in: context, name: "Level \(index)", parent: parent)
            deepChain.append(child)
            parent = child
        }
        check(parent.depth == 40, "Deep nesting should keep its depth")
        check(work.groupCount == 42, "Deep nesting should count all subgroups")

        // Updating a snippet.
        SnippetStore.update(greeting, name: "Updated", content: "Updated content", in: context)
        check(greeting.name == "Updated", "Snippet name should update")
        check(greeting.content == "Updated content", "Snippet content should update")

        // Deleting a subtree must cascade to child groups and snippets.
        SnippetStore.delete(email, in: context)
        let groupCount = try context.fetchCount(FetchDescriptor<SnippetGroup>())
        let snippetCount = try context.fetchCount(FetchDescriptor<Snippet>())
        check(!snippetExists(greeting, in: context), "Deleting a group should delete its snippets")
        check(!work.children.contains { $0.id == email.id }, "Deleting a group should remove it from its parent")
        check(groupCount == 41, "Only the remaining deep chain should be left, got \(groupCount)")
        check(snippetCount == 1, "Only the Work-level snippet should be left, got \(snippetCount)")

        // Deleting a single snippet should remove it from its group immediately.
        if let remaining = try context.fetch(FetchDescriptor<Snippet>()).first {
            let parent = remaining.group
            SnippetStore.delete(remaining, in: context)
            let remainingCount = try context.fetchCount(FetchDescriptor<Snippet>())
            check(remainingCount == 0, "Deleting a snippet should remove it from the store")
            check(parent?.snippets.isEmpty == true, "Deleting a snippet should update its group")
        } else {
            failures.append("Expected one remaining snippet before the single-delete check")
        }

        let moveConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let moveContainer = try ModelContainer(for: schema, configurations: [moveConfiguration])
        let moveContext = ModelContext(moveContainer)
        runMoveTests(in: moveContext)

        try runBackupTests(schema: schema)
    }

    private static func runMoveTests(in context: ModelContext) {
        let alpha = SnippetStore.createGroup(in: context, name: "Alpha", parent: nil)
        let beta = SnippetStore.createGroup(in: context, name: "Beta", parent: nil)
        let gamma = SnippetStore.createGroup(in: context, name: "Gamma", parent: nil)
        let delta = SnippetStore.createGroup(in: context, name: "Delta", parent: nil)

        check(rootNames(in: context) == ["Alpha", "Beta", "Gamma", "Delta"], "New groups should append in order")

        // Reorder root groups by moving Delta before Beta.
        check(SnippetStore.moveGroup(delta, near: beta, position: .before, in: context), "Moving a root group near another should succeed")
        check(rootNames(in: context) == ["Alpha", "Delta", "Beta", "Gamma"], "Root groups should reorder")
        check(rootGroups(in: context).map(\.sortIndex) == Array(0..<4), "Root groups should have contiguous indexes")

        // Nest Gamma inside Alpha, then move Delta after Gamma into the same group.
        check(SnippetStore.moveGroup(gamma, into: alpha, in: context), "Moving a group into another should succeed")
        check(gamma.parent?.id == alpha.id, "Gamma should have Alpha as its parent")
        check(alpha.orderedChildren.map(\.name) == ["Gamma"], "Alpha should contain Gamma")
        check(rootNames(in: context) == ["Alpha", "Delta", "Beta"], "Gamma should leave the root level")

        check(SnippetStore.moveGroup(delta, near: gamma, position: .after, in: context), "Moving a group near a nested group should succeed")
        check(delta.parent?.id == alpha.id, "Delta should move into Gamma's parent")
        check(alpha.orderedChildren.map(\.name) == ["Gamma", "Delta"], "Sibling groups should insert at the requested position")
        check(rootNames(in: context) == ["Alpha", "Beta"], "Root groups should update after a nested move")

        // A group must never become its own descendant.
        check(!SnippetStore.moveGroup(alpha, into: delta, in: context), "Moving a group into its descendant should fail")
        check(!SnippetStore.moveGroup(alpha, near: delta, position: .after, in: context), "Moving a group near its descendant should fail")
        check(alpha.parent == nil, "A rejected move should not change the parent")

        // Snippet reordering and moving between groups.
        let one = SnippetStore.createSnippet(in: context, name: "One", content: "1", group: alpha)
        let two = SnippetStore.createSnippet(in: context, name: "Two", content: "2", group: alpha)
        let three = SnippetStore.createSnippet(in: context, name: "Three", content: "3", group: beta)

        let dragProvider = SnippetDragPayload.provider(for: .snippet(one))
        check(
            dragProvider.hasItemConformingToTypeIdentifier(SnippetDragPayload.typeIdentifier),
            "Drag payload should register the app's private drag type"
        )

        check(alpha.orderedSnippets.map(\.name) == ["One", "Two"], "Snippets should append in order")
        check(SnippetStore.moveSnippet(two, into: beta, in: context), "Moving a snippet into another group should succeed")
        check(two.group?.id == beta.id, "Two should belong to Beta")
        check(beta.orderedSnippets.map(\.name) == ["Three", "Two"], "Moving into a group should append")
        check(alpha.orderedSnippets.map(\.name) == ["One"], "The old group should lose the snippet")

        check(SnippetStore.moveSnippet(two, near: three, position: .before, in: context), "Reordering snippets should succeed")
        check(beta.orderedSnippets.map(\.name) == ["Two", "Three"], "Snippets should reorder")
        check(beta.orderedSnippets.map(\.sortIndex) == [0, 1], "Snippet indexes should be contiguous")

        check(SnippetStore.moveSnippet(one, near: two, position: .after, in: context), "Moving a snippet between groups near a snippet should succeed")
        check(beta.orderedSnippets.map(\.name) == ["Two", "One", "Three"], "Snippet insertion should use the target position")
        check(alpha.orderedSnippets.isEmpty, "The source group should be empty")

        // Return Beta to the root after Alpha and detach Gamma to the root.
        check(SnippetStore.moveGroup(beta, near: alpha, position: .after, in: context), "Moving a group back to the root should succeed")
        check(beta.parent == nil, "Beta should be at the root again")
        check(rootNames(in: context) == ["Alpha", "Beta"], "Root order should include the returned group")

        check(SnippetStore.moveGroup(gamma, near: alpha, position: .before, in: context), "Moving a nested group to the root should succeed")
        check(gamma.parent == nil, "Gamma should be at the root")
        check(rootNames(in: context) == ["Gamma", "Alpha", "Beta"], "Detached group should insert before its target")
        check(alpha.orderedChildren.map(\.name) == ["Delta"], "Alpha should keep its remaining child")
        check(rootGroups(in: context).map(\.sortIndex) == Array(0..<3), "Root indexes should be contiguous after moves")
    }

    private static func runBackupTests(schema: Schema) throws {
        let sourceConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let sourceContainer = try ModelContainer(for: schema, configurations: [sourceConfiguration])
        let sourceContext = ModelContext(sourceContainer)

        let work = SnippetStore.createGroup(in: sourceContext, name: "Work", parent: nil)
        work.iconName = "briefcase"
        try sourceContext.save()
        let email = SnippetStore.createGroup(in: sourceContext, name: "Email", parent: work)
        let signature = SnippetStore.createSnippet(
            in: sourceContext,
            name: "Signature",
            content: "Best regards,\nAlex",
            group: email
        )
        signature.isHidden = true
        try sourceContext.save()
        _ = SnippetStore.createSnippet(
            in: sourceContext,
            name: "Reply",
            content: "Thanks for the quick reply.",
            group: work
        )

        let configuration = BackupConfiguration(pasteAutomatically: false, launchAtLogin: true)
        let backup = try SnippetBackup.makeBackup(in: sourceContext, configuration: configuration)

        check(backup.formatVersion == SnippyBackup.currentFormatVersion, "Backups should use the current format")
        check(backup.counts == SnippetBackupCounts(groups: 2, snippets: 2), "Backup counts should include nested items")
        check(backup.configuration == configuration, "Backup should preserve configuration")

        let data = try SnippetBackup.encode(backup)
        let decoded = try SnippetBackup.decode(data)

        check(decoded.counts == backup.counts, "Decoded backup counts should match")
        check(decoded.groups.first?.name == "Work", "Decoded backup should preserve root groups")
        check(decoded.groups.first?.iconName == "briefcase", "Decoded backup should preserve folder icons")
        check(decoded.groups.first?.children.first?.name == "Email", "Decoded backup should preserve nested groups")
        check(
            decoded.groups.first?.children.first?.snippets.first?.content == "Best regards,\nAlex",
            "Decoded backup should preserve multiline content"
        )
        check(
            decoded.groups.first?.children.first?.snippets.first?.isHidden == true,
            "Decoded backup should preserve hidden snippets"
        )

        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "snippy-self-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            try SnippetBackup.write(backup, to: fileURL)
            let fileBackup = try SnippetBackup.read(from: fileURL)
            check(fileBackup.counts == backup.counts, "Backup file should round-trip through disk")
        } catch {
            failures.append("backup file round-trip failed: \(error)")
        }

        var futureBackup = backup
        futureBackup.formatVersion = SnippyBackup.currentFormatVersion + 1
        let futureData = try SnippetBackup.encode(futureBackup)
        check((try? SnippetBackup.decode(futureData)) == nil, "Newer backup formats should be rejected")
        check((try? SnippetBackup.decode(Data("{}".utf8))) == nil, "Invalid JSON should be rejected")

        let targetConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let targetContainer = try ModelContainer(for: schema, configurations: [targetConfiguration])
        let targetContext = ModelContext(targetContainer)
        _ = SnippetStore.createGroup(in: targetContext, name: "Old", parent: nil)

        let counts = try SnippetBackup.replaceSnippets(in: targetContext, with: decoded)
        check(counts == backup.counts, "Restore should report the imported item counts")

        let restoredRoots = rootGroups(in: targetContext)
        check(restoredRoots.map(\.name) == ["Work"], "Restore should replace the previous root groups")
        check(restoredRoots.first?.iconName == "briefcase", "Restore should recreate folder icons")
        check(restoredRoots.first?.children.map(\.name) == ["Email"], "Restore should recreate nested groups")
        check(restoredRoots.first?.orderedSnippets.map(\.name) == ["Reply"], "Restore should recreate snippets")
        check(
            restoredRoots.first?.children.first?.orderedSnippets.map(\.name) == ["Signature"],
            "Restore should recreate nested snippets"
        )
        check(
            restoredRoots.first?.children.first?.orderedSnippets.first?.isSecret == true,
            "Restore should recreate hidden snippets"
        )

        let restoredGroupCount = try targetContext.fetchCount(FetchDescriptor<SnippetGroup>())
        let restoredSnippetCount = try targetContext.fetchCount(FetchDescriptor<Snippet>())
        check(restoredGroupCount == 2, "Restore should not leave old groups")
        check(restoredSnippetCount == 2, "Restore should not leave old snippets")
    }

    private static func rootNames(in context: ModelContext) -> [String] {
        rootGroups(in: context).map(\.name)
    }

    private static func rootGroups(in context: ModelContext) -> [SnippetGroup] {
        let groups = (try? context.fetch(FetchDescriptor<SnippetGroup>())) ?? []
        return SnippetStore.rootGroups(from: groups)
    }

    private static func snippetExists(_ snippet: Snippet, in context: ModelContext) -> Bool {
        let snippets = (try? context.fetch(FetchDescriptor<Snippet>())) ?? []
        return snippets.contains { $0.id == snippet.id }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures.append(message)
        }
    }

    private static func write(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
#endif
