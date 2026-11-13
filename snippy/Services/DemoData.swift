//
//  DemoData.swift
//  snippy
//

#if DEBUG
import Foundation
import OSLog
import SwiftData

/// Seeds a separate demo store for screenshots and local UI work.
///
/// Enabled only with `--demo` in Debug builds. It never touches the user's
/// normal `Snippets.store`.
@MainActor
enum DemoData {
    static func seedIfRequested() {
        guard CommandLine.arguments.contains("--demo") else { return }

        let context = ModelContext(SnippetStorage.container)

        do {
            let existingGroups = try context.fetchCount(FetchDescriptor<SnippetGroup>())
            let existingSnippets = try context.fetchCount(FetchDescriptor<Snippet>())
            guard existingGroups == 0, existingSnippets == 0 else { return }

            seed(into: context)
            try context.save()
        } catch {
            AppLog.storage.error("Failed to seed demo data: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func seed(into context: ModelContext) {
        var timestamp = Date.now.addingTimeInterval(-200)

        func nextDate() -> Date {
            timestamp = timestamp.addingTimeInterval(1)
            return timestamp
        }

        func group(_ name: String, parent: SnippetGroup? = nil, icon: String? = nil) -> SnippetGroup {
            let group = SnippetGroup(name: name, createdAt: nextDate(), iconName: icon)
            context.insert(group)
            group.parent = parent
            return group
        }

        func snippet(_ name: String, _ content: String, in group: SnippetGroup) {
            let snippet = Snippet(name: name, content: content, createdAt: nextDate())
            context.insert(snippet)
            snippet.group = group
        }

        let work = group("Work", icon: "briefcase")
        let email = group("Email", parent: work, icon: "envelope")
        let signatures = group("Signatures", parent: email, icon: "signature")
        snippet(
            "Formal sign-off",
            """
            Best regards,
            Alex
            """,
            in: signatures
        )
        snippet(
            "Short sign-off",
            "Thanks,\nAlex",
            in: signatures
        )
        snippet(
            "Follow-up nudge",
            """
            Hi there,

            Just floating this back to the top of your inbox in case it slipped through. Happy to answer any questions.

            Thanks!
            """,
            in: email
        )
        snippet(
            "Quick reply",
            "Thanks for the quick reply — that's exactly what I needed.",
            in: email
        )

        let code = group("Code", parent: work, icon: "chevron.left.forwardslash.chevron.right")
        let swift = group("Swift", parent: code, icon: "curlybraces")
        snippet(
            "SwiftUI sheet",
            """
            .sheet(isPresented: $isPresented) {
                EditorView()
            }
            """,
            in: swift
        )
        snippet(
            "Observable model",
            """
            @Observable
            final class Model {
                var items: [Item] = []
            }
            """,
            in: swift
        )
        let shell = group("Shell", parent: code, icon: "terminal")
        snippet(
            "Largest files",
            "du -sh * | sort -h",
            in: shell
        )
        snippet(
            "Meeting notes",
            """
            Decisions
            • Ship the first version on Friday
            • Keep the next iteration small

            Action items
            • Update the empty state
            • Add the onboarding screen
            """,
            in: work
        )

        let personal = group("Personal", icon: "person")
        let address = group("Address", parent: personal, icon: "house")
        snippet(
            "Shipping address",
            """
            123 Example Street
            Springfield
            """,
            in: address
        )
        snippet(
            "Coffee order",
            "Flat white, oat milk, one sugar.",
            in: personal
        )
        snippet(
            "Support email",
            "help@example.com",
            in: personal
        )

        let travel = group("Travel", icon: "airplane")
        snippet(
            "Packing checklist",
            """
            Charger
            Headphones
            Notebook
            """,
            in: travel
        )
        snippet(
            "Airport transfer",
            "Terminal 2 → city center, 40 minutes.",
            in: travel
        )

        let snippets = group("Snippets", icon: "doc.on.doc")
        snippet(
            "Email address",
            "hello@example.com",
            in: snippets
        )
        snippet(
            "Calendar link",
            "https://cal.com/example/30min",
            in: snippets
        )
    }
}
#endif
