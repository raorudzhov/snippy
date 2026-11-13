//
//  GroupDetailView.swift
//  snippy
//

import SwiftUI

/// Callbacks supplied by the Snippets tab to the group detail pane.
struct GroupDetailActions {
    var selectGroup: (SnippetGroup) -> Void
    var newSnippet: (SnippetGroup) -> Void
    var newGroup: (SnippetGroup) -> Void
    var renameGroup: (SnippetGroup) -> Void
    var customizeIcon: (SnippetGroup) -> Void
    var deleteGroup: (SnippetGroup) -> Void
    var snippet: SnippetCardActions
    var move: (DraggedItem, DragTarget) -> Void
}

/// The right-hand pane for the selected group: breadcrumbs, child groups and
/// snippet cards.
struct GroupDetailView: View {
    let group: SnippetGroup
    let actions: GroupDetailActions

    private var children: [SnippetGroup] {
        group.orderedChildren
    }

    private var snippets: [Snippet] {
        group.orderedSnippets
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.5)
                .padding(.horizontal, Theme.horizontalPadding)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !children.isEmpty {
                        groupsSection
                    }

                    snippetsSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            if group.depth > 0 {
                BreadcrumbView(group: group, selectGroup: actions.selectGroup)
            }

            HStack(alignment: .center, spacing: 7) {
                Image(systemName: group.displayIconName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.tint)

                Text(group.name)
                    .font(.system(size: 21, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 10)

                groupMenu
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
        let snippetCount = snippets.count
        let groupCount = children.count

        if snippetCount == 0, groupCount == 0 {
            return "Empty group"
        }

        var parts: [String] = []
        if snippetCount > 0 {
            parts.append("\(snippetCount) \(snippetCount == 1 ? "snippet" : "snippets")")
        }
        if groupCount > 0 {
            parts.append("\(groupCount) \(groupCount == 1 ? "group" : "groups")")
        }
        return parts.joined(separator: " · ")
    }

    private var groupMenu: some View {
        Menu {
            Button {
                actions.newSnippet(group)
            } label: {
                Label("New Snippet", systemImage: "doc.badge.plus")
            }

            Button {
                actions.newGroup(group)
            } label: {
                Label("New Group", systemImage: "folder.badge.plus")
            }

            Divider()

            Button {
                actions.renameGroup(group)
            } label: {
                Label("Rename Group", systemImage: "pencil")
            }

            Button {
                actions.customizeIcon(group)
            } label: {
                Label("Customize Icon", systemImage: "paintpalette")
            }

            Divider()

            Button(role: .destructive) {
                actions.deleteGroup(group)
            } label: {
                Label("Delete Group", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.055))
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Group actions")
        .accessibilityLabel("Group actions")
    }

    // MARK: - Groups

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionTitle(title: "Groups", count: children.count)

            VStack(spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.element.id) { index, child in
                    if index > 0 {
                        Divider()
                            .opacity(0.5)
                            .padding(.leading, 38)
                    }

                    SubgroupRow(group: child, actions: actions)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .fill(Color.snippetFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.7)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        }
    }

    // MARK: - Snippets

    private var snippetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SectionTitle(title: "Snippets", count: snippets.count)

                Spacer()

                SmallAddButton {
                    actions.newSnippet(group)
                }
            }

            if snippets.isEmpty {
                emptySnippets
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(snippets, id: \.id) { snippet in
                        SnippetCardView(snippet: snippet, actions: actions.snippet)
                    }
                }
            }
        }
    }

    private var emptySnippets: some View {
        VStack(spacing: 7) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)

            Text("No snippets yet")
                .font(.system(size: 12.5, weight: .medium))

            Text("Add one and click it whenever you need it.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            Button("New Snippet") {
                actions.newSnippet(group)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Color.snippetFill.opacity(0.65))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.035), lineWidth: 0.7)
        }
    }
}

// MARK: - Section title

private struct SectionTitle: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Subgroup row

private struct SubgroupRow: View {
    let group: SnippetGroup
    let actions: GroupDetailActions

    @Environment(SnippetDragState.self) private var dragState
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: group.displayIconName)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)

            Text(group.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            if group.snippetCount > 0 {
                Text("\(group.snippetCount)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 12)
                .opacity(isHovered ? 0.75 : 0)
                .allowsHitTesting(false)

            Image(systemName: "chevron.right")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isHovered ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            actions.selectGroup(group)
        }
        .onHover { isHovered = $0 }
        .overlay {
            if let target = dragState.hoverTarget,
               target.kind == .group,
               target.id == group.id {
                DropIndicator(zone: target.zone)
            }
        }
        .onDrag {
            dragState.begin(.group(group))
            return SnippetDragPayload.provider(for: .group(group))
        }
        .onDrop(
            of: [SnippetDragPayload.typeIdentifier],
            delegate: GroupDropDelegate(
                group: group,
                height: 34,
                dragState: dragState,
                move: actions.move
            )
        )
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .animation(.easeOut(duration: 0.08), value: dragState.hoverTarget)
        .contextMenu {
            Button {
                actions.selectGroup(group)
            } label: {
                Label("Open Group", systemImage: "folder")
            }

            Divider()

            Button {
                actions.newGroup(group)
            } label: {
                Label("New Group", systemImage: "folder.badge.plus")
            }

            Button {
                actions.newSnippet(group)
            } label: {
                Label("New Snippet", systemImage: "doc.badge.plus")
            }

            Divider()

            Button {
                actions.renameGroup(group)
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                actions.customizeIcon(group)
            } label: {
                Label("Customize Icon", systemImage: "paintpalette")
            }

            Divider()

            Button(role: .destructive) {
                actions.deleteGroup(group)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .help(group.name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            actions.selectGroup(group)
        }
    }
}

// MARK: - Small add button

private struct SmallAddButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("Add")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(isHovered ? Color.accentColor : .secondary)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.045))
            }
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .help("Add a snippet to this group")
    }
}

// MARK: - Breadcrumb

private struct BreadcrumbView: View {
    let group: SnippetGroup
    let selectGroup: (SnippetGroup) -> Void

    private var ancestors: [SnippetGroup] {
        Array(group.ancestry.dropLast())
    }

    var body: some View {
        HStack(spacing: 3) {
            if ancestors.count > 3 {
                breadcrumbButton(ancestors[0])

                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.quaternary)

                hiddenAncestorsMenu

                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.quaternary)

                breadcrumbButton(ancestors[ancestors.count - 2])
                separator
                breadcrumbButton(ancestors[ancestors.count - 1])
            } else {
                ForEach(Array(ancestors.enumerated()), id: \.element.id) { index, ancestor in
                    if index > 0 {
                        separator
                    }
                    breadcrumbButton(ancestor)
                }
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7, weight: .semibold))
            .foregroundStyle(.quaternary)
    }

    private func breadcrumbButton(_ group: SnippetGroup) -> some View {
        Button {
            selectGroup(group)
        } label: {
            Text(group.name)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .help(group.name)
    }

    private var hiddenAncestorsMenu: some View {
        Menu {
            ForEach(ancestors.dropFirst().dropLast(2), id: \.id) { ancestor in
                Button(ancestor.name) {
                    selectGroup(ancestor)
                }
            }
        } label: {
            Text("…")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Show parent groups")
    }
}
