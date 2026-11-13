//
//  AllSnippetsView.swift
//  snippy
//

import SwiftUI

/// Every snippet in the library, grouped by its folder.
struct AllSnippetsView: View {
    let groups: [SnippetGroup]
    let snippetActions: SnippetCardActions

    private struct SnippetSection: Identifiable {
        let group: SnippetGroup
        let snippets: [Snippet]

        var id: UUID { group.id }
    }

    private var sections: [SnippetSection] {
        var result: [SnippetSection] = []

        func collect(_ group: SnippetGroup) {
            let snippets = group.orderedSnippets
            if !snippets.isEmpty {
                result.append(SnippetSection(group: group, snippets: snippets))
            }

            for child in group.orderedChildren {
                collect(child)
            }
        }

        for group in groups {
            collect(group)
        }
        return result
    }

    private var snippetCount: Int {
        sections.reduce(0) { $0 + $1.snippets.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.5)
                .padding(.horizontal, Theme.horizontalPadding)

            if sections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 7) {
                                sectionHeader(section)

                                VStack(spacing: 7) {
                                    ForEach(section.snippets, id: \.id) { snippet in
                                        SnippetCardView(snippet: snippet, actions: snippetActions)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 7) {
                Image(systemName: "tray.full")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.tint)

                Text("All Snippets")
                    .font(.system(size: 21, weight: .semibold))

                Spacer(minLength: 10)
            }

            Text(summary)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var summary: String {
        guard !sections.isEmpty else { return "No snippets yet" }

        let snippets = "\(snippetCount) \(snippetCount == 1 ? "snippet" : "snippets")"
        let folders = "\(sections.count) \(sections.count == 1 ? "folder" : "folders")"
        return "\(snippets) in \(folders)"
    }

    private func sectionHeader(_ section: SnippetSection) -> some View {
        HStack(spacing: 5) {
            Image(systemName: section.group.displayIconName)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.tint)

            Text(section.group.ancestry.map(\.name).joined(separator: " / "))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("\(section.snippets.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No snippets yet")
                .font(.system(size: 12.5, weight: .medium))

            Text("Select a folder in the sidebar to add one.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
