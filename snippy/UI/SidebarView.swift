//
//  SidebarView.swift
//  snippy
//

import SwiftUI

/// Callbacks needed by the folder sidebar.
struct SidebarActions {
    var select: (SnippetGroup) -> Void
    var selectAllSnippets: () -> Void
    /// `nil` creates a top-level group; a group creates one inside it.
    var newGroup: (SnippetGroup?) -> Void
    var newSnippet: (SnippetGroup) -> Void
    var rename: (SnippetGroup) -> Void
    var customizeIcon: (SnippetGroup) -> Void
    var delete: (SnippetGroup) -> Void
    var move: (DraggedItem, DragTarget) -> Void
}

/// The left pane of the Snippets tab: All Snippets plus the recursive folder tree.
///
/// Right-clicking empty space creates a top-level group; right-clicking a group
/// creates one inside it.
struct SidebarView: View {
    let groups: [SnippetGroup]
    @Binding var isAllSnippetsSelected: Bool
    @Binding var selectedGroupID: UUID?
    @Binding var expandedGroupIDs: Set<UUID>
    let actions: SidebarActions

    @State private var isAllSnippetsHovered = false

    var body: some View {
        ZStack {
            // The transparent layer and the scroll view both offer New Group,
            // so right-clicking empty space works at any scroll position.
            Color.clear
                .contentShape(Rectangle())
                .contextMenu {
                    newGroupMenuItem
                }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    allSnippetsRow
                        .padding(.top, 4)

                    Color.clear
                        .frame(height: 8)

                    if groups.isEmpty {
                        emptyState
                    } else {
                        ForEach(groups, id: \.id) { group in
                            GroupTreeRow(
                                group: group,
                                depth: 0,
                                isAllSnippetsSelected: isAllSnippetsSelected,
                                selectedGroupID: $selectedGroupID,
                                expandedGroupIDs: $expandedGroupIDs,
                                actions: actions
                            )
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .contextMenu {
                newGroupMenuItem
            }
        }
        .background(Color.sidebarFill)
    }

    private var allSnippetsRow: some View {
        Button {
            actions.selectAllSnippets()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(isAllSnippetsSelected ? Color.white : Color.accentColor)
                    .frame(width: 16, alignment: .center)

                Text("All Snippets")
                    .font(.system(size: 13, weight: isAllSnippetsSelected ? .medium : .regular))
                    .foregroundStyle(isAllSnippetsSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Theme.treeRowHeight)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isAllSnippetsSelected
                            ? Color.accentColor
                            : (isAllSnippetsHovered ? Color.primary.opacity(0.055) : Color.clear)
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isAllSnippetsHovered = hovering
        }
        .help("Show every snippet")
        .accessibilityAddTraits(isAllSnippetsSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var newGroupMenuItem: some View {
        Button {
            actions.newGroup(nil)
        } label: {
            Label("New Group", systemImage: "folder.badge.plus")
        }
    }

    private var emptyState: some View {
        Text("No folders yet")
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }
}

private struct GroupTreeRow: View {
    let group: SnippetGroup
    let depth: Int
    let isAllSnippetsSelected: Bool
    @Binding var selectedGroupID: UUID?
    @Binding var expandedGroupIDs: Set<UUID>
    let actions: SidebarActions

    @Environment(SnippetDragState.self) private var dragState
    @State private var isHovered = false

    private var isSelected: Bool {
        !isAllSnippetsSelected && selectedGroupID == group.id
    }

    private var isExpanded: Bool {
        expandedGroupIDs.contains(group.id)
    }

    private var hasChildren: Bool {
        !group.children.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row
                .id(group.id)

            if isExpanded {
                ForEach(group.orderedChildren, id: \.id) { child in
                    GroupTreeRow(
                        group: child,
                        depth: depth + 1,
                        isAllSnippetsSelected: isAllSnippetsSelected,
                        selectedGroupID: $selectedGroupID,
                        expandedGroupIDs: $expandedGroupIDs,
                        actions: actions
                    )
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 4) {
            Button {
                toggleExpansion()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 13, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hasChildren ? 1 : 0)
            .disabled(!hasChildren)
            .animation(.easeOut(duration: 0.14), value: isExpanded)

            HStack(spacing: 6) {
                Image(systemName: group.displayIconName)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 16, alignment: .center)

                Text(group.name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                actions.select(group)
            }
        }
        .padding(.leading, 3 + CGFloat(depth) * 14)
        .padding(.trailing, 6)
        .frame(height: Theme.treeRowHeight)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(backgroundColor)
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
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
                height: Theme.treeRowHeight,
                dragState: dragState,
                move: actions.move
            )
        )
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .animation(.easeOut(duration: 0.08), value: dragState.hoverTarget)
        .contextMenu {
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
                actions.rename(group)
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
                actions.delete(group)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .help(group.name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor
        }
        if isHovered {
            return Color.primary.opacity(0.055)
        }
        return .clear
    }

    private func toggleExpansion() {
        withAnimation(.easeOut(duration: 0.16)) {
            if isExpanded {
                expandedGroupIDs.remove(group.id)
            } else {
                expandedGroupIDs.insert(group.id)
            }
        }
    }
}
