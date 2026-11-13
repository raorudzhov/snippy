//
//  SnippetsView.swift
//  snippy
//

import SwiftData
import SwiftUI

/// The Snippets tab: selection, overlays, drag and drop, and persistence glue
/// around the sidebar and group detail pane.
struct SnippetsView: View {
    let actions: SnippetsActions

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SnippetGroup.createdAt) private var groups: [SnippetGroup]
    @AppStorage("snippy.sidebarWidth") private var sidebarWidth = Double(Theme.sidebarWidth)

    @State private var selectedGroupID: UUID?
    @State private var isAllSnippetsSelected = true
    @State private var expandedGroupIDs: Set<UUID> = []
    @State private var editor: EditorState?
    @State private var deletion: DeleteRequest?
    @State private var iconPicker: IconPickerState?
    @State private var didPerformInitialSelection = false
    @State private var dragState = SnippetDragState()

    private var rootGroups: [SnippetGroup] {
        SnippetStore.rootGroups(from: groups)
    }

    private var selectedGroup: SnippetGroup? {
        guard let selectedGroupID else { return nil }
        return groups.first { $0.id == selectedGroupID }
    }

    private var isOverlayPresented: Bool {
        editor != nil || deletion != nil || iconPicker != nil
    }

    private var sidebarWidthValue: CGFloat {
        let width = CGFloat(sidebarWidth)
        guard width.isFinite else { return Theme.sidebarWidth }
        return min(max(width, Theme.sidebarMinWidth), Theme.sidebarMaxWidth)
    }

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                SidebarView(
                    groups: rootGroups,
                    isAllSnippetsSelected: $isAllSnippetsSelected,
                    selectedGroupID: $selectedGroupID,
                    expandedGroupIDs: $expandedGroupIDs,
                    actions: sidebarActions
                )
                .frame(width: sidebarWidthValue)

                SidebarResizeHandle(
                    width: $sidebarWidth,
                    minimumWidth: Theme.sidebarMinWidth,
                    maximumWidth: Theme.sidebarMaxWidth,
                    defaultWidth: Theme.sidebarWidth
                )

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let editor {
                EditorOverlay(
                    state: editor,
                    onSave: { name, content, isHidden in
                        saveEditor(editor, name: name, content: content, isHidden: isHidden)
                    },
                    onCancel: {
                        dismissEditor()
                    }
                )
                .id(editor.id)
                .zIndex(2)
            }

            if let deletion {
                DeleteConfirmationView(
                    request: deletion,
                    onDelete: {
                        confirmDeletion(deletion)
                    },
                    onCancel: {
                        dismissDeletion()
                    }
                )
                .id(deletion.id)
                .zIndex(3)
            }

            if let iconPicker {
                IconPickerOverlay(
                    state: iconPicker,
                    onSave: { symbol in
                        saveIcon(symbol, for: iconPicker)
                    },
                    onCancel: {
                        dismissIconPicker()
                    }
                )
                .id(iconPicker.id)
                .zIndex(4)
            }
        }
        .environment(dragState)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            performInitialSelectionIfNeeded()
        }
        .onChange(of: groups.map(\.id)) {
            if selectedGroup == nil, !isAllSnippetsSelected {
                performInitialSelectionIfNeeded(force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .snippySettingsWindowDidShow)) { _ in
            if selectedGroup == nil, !isAllSnippetsSelected {
                performInitialSelectionIfNeeded(force: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .snippySettingsWindowDidClose)) { _ in
            dragState.end()
            dismissEditor()
            dismissDeletion()
            dismissIconPicker()
        }
        .onReceive(NotificationCenter.default.publisher(for: .snippyBackupDidImport)) { _ in
            dragState.end()
            dismissEditor()
            dismissDeletion()
            dismissIconPicker()
        }
        // Escape dismisses the topmost overlay first, then closes Settings.
        .onReceive(NotificationCenter.default.publisher(for: .snippyEscapePressed)) { _ in
            if iconPicker != nil {
                dismissIconPicker()
            } else if editor != nil {
                dismissEditor()
            } else if deletion != nil {
                dismissDeletion()
            } else {
                actions.close()
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if rootGroups.isEmpty {
            WelcomeView(onCreateGroup: startNewRootGroup)
        } else if isAllSnippetsSelected {
            AllSnippetsView(groups: rootGroups, snippetActions: detailActions.snippet)
        } else if let selectedGroup {
            GroupDetailView(group: selectedGroup, actions: detailActions)
        } else {
            EmptyDetailView()
        }
    }

    // MARK: - Actions

    private var sidebarActions: SidebarActions {
        SidebarActions(
            select: { group in
                selectGroup(group)
            },
            selectAllSnippets: {
                isAllSnippetsSelected = true
                selectedGroupID = nil
            },
            newGroup: { group in
                startNewGroup(parent: group)
            },
            newSnippet: { group in
                startNewSnippet(in: group)
            },
            rename: { group in
                startRename(group)
            },
            customizeIcon: { group in
                startIconPicker(for: group)
            },
            delete: { group in
                requestDeletion(of: group)
            },
            move: performMove
        )
    }

    private var detailActions: GroupDetailActions {
        GroupDetailActions(
            selectGroup: { group in
                selectGroup(group)
            },
            newSnippet: { group in
                startNewSnippet(in: group)
            },
            newGroup: { group in
                startNewGroup(parent: group)
            },
            renameGroup: { group in
                startRename(group)
            },
            customizeIcon: { group in
                startIconPicker(for: group)
            },
            deleteGroup: { group in
                requestDeletion(of: group)
            },
            snippet: SnippetCardActions(
                activate: { snippet in
                    startEditing(snippet)
                },
                copy: { snippet in
                    actions.copySnippet(snippet)
                },
                delete: { snippet in
                    requestDeletion(of: snippet)
                },
                move: performMove
            ),
            move: performMove
        )
    }

    private func startNewRootGroup() {
        startNewGroup(parent: nil)
    }

    private func startNewGroup(parent: SnippetGroup?) {
        guard !isOverlayPresented else { return }

        if let parent {
            expandAncestors(of: parent)
        }

        let context: String
        if let parent {
            context = "In " + parent.ancestry.map(\.name).joined(separator: " / ")
        } else {
            context = "Top level"
        }

        withAnimation(.easeOut(duration: 0.14)) {
            editor = EditorState(
                kind: .newGroup(parentID: parent?.id),
                initialName: "",
                initialContent: "",
                contextDescription: context,
                initialHidden: false
            )
        }
    }

    private func startRename(_ group: SnippetGroup) {
        guard !isOverlayPresented else { return }

        let context = group.parent == nil
            ? "Top level"
            : "In " + (group.parent?.ancestry.map(\.name).joined(separator: " / ") ?? "")

        withAnimation(.easeOut(duration: 0.14)) {
            editor = EditorState(
                kind: .renameGroup(groupID: group.id),
                initialName: group.name,
                initialContent: "",
                contextDescription: context,
                initialHidden: false
            )
        }
    }

    private func startNewSnippet(in group: SnippetGroup) {
        guard !isOverlayPresented else { return }

        withAnimation(.easeOut(duration: 0.14)) {
            editor = EditorState(
                kind: .newSnippet(groupID: group.id),
                initialName: "",
                initialContent: "",
                contextDescription: "In " + group.ancestry.map(\.name).joined(separator: " / "),
                initialHidden: false
            )
        }
    }

    private func startEditing(_ snippet: Snippet) {
        guard !isOverlayPresented else { return }

        let path = snippet.group?.ancestry.map(\.name).joined(separator: " / ") ?? ""
        withAnimation(.easeOut(duration: 0.14)) {
            editor = EditorState(
                kind: .editSnippet(snippetID: snippet.id),
                initialName: snippet.name,
                initialContent: snippet.content,
                contextDescription: path.isEmpty ? nil : "In " + path,
                initialHidden: snippet.isSecret
            )
        }
    }

    private func startIconPicker(for group: SnippetGroup) {
        guard !isOverlayPresented else { return }

        withAnimation(.easeOut(duration: 0.14)) {
            iconPicker = IconPickerState(
                groupID: group.id,
                groupName: group.name,
                initialSymbol: group.displayIconName
            )
        }
    }

    private func dismissIconPicker() {
        guard iconPicker != nil else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            iconPicker = nil
        }
    }

    private func saveIcon(_ symbol: String, for state: IconPickerState) {
        guard let group = groups.first(where: { $0.id == state.groupID }) else {
            dismissIconPicker()
            return
        }

        SnippetStore.updateIcon(group, to: symbol, in: modelContext)
        dismissIconPicker()
    }

    private func dismissEditor() {
        guard editor != nil else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            editor = nil
        }
    }

    private func dismissDeletion() {
        guard deletion != nil else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            deletion = nil
        }
    }

    // MARK: - Saving

    private func saveEditor(_ state: EditorState, name: String, content: String, isHidden: Bool) {
        switch state.kind {
        case .newGroup(let parentID):
            let parent = parentID.flatMap { id in groups.first { $0.id == id } }
            let group = SnippetStore.createGroup(in: modelContext, name: name, parent: parent)

            withAnimation(.easeOut(duration: 0.16)) {
                if let parent {
                    expandedGroupIDs.insert(parent.id)
                }
                isAllSnippetsSelected = false
                selectedGroupID = group.id
                editor = nil
            }

        case .renameGroup(let groupID):
            guard let group = groups.first(where: { $0.id == groupID }) else {
                dismissEditor()
                return
            }
            SnippetStore.rename(group, to: name, in: modelContext)
            dismissEditor()

        case .newSnippet(let groupID):
            guard let group = groups.first(where: { $0.id == groupID }) else {
                dismissEditor()
                return
            }
            SnippetStore.createSnippet(
                in: modelContext,
                name: name,
                content: content,
                group: group,
                isHidden: isHidden
            )

            withAnimation(.easeOut(duration: 0.16)) {
                isAllSnippetsSelected = false
                selectedGroupID = group.id
                expandAncestors(of: group)
                editor = nil
            }

        case .editSnippet(let snippetID):
            guard let snippet = findSnippet(withID: snippetID) else {
                dismissEditor()
                return
            }
            SnippetStore.update(
                snippet,
                name: name,
                content: content,
                isHidden: isHidden,
                in: modelContext
            )

            withAnimation(.easeOut(duration: 0.16)) {
                if !isAllSnippetsSelected, let group = snippet.group {
                    selectedGroupID = group.id
                    expandAncestors(of: group)
                }
                editor = nil
            }
        }
    }

    // MARK: - Deleting

    private func requestDeletion(of group: SnippetGroup) {
        guard !isOverlayPresented else { return }

        var parts: [String] = []
        if group.snippetCount > 0 {
            let count = group.snippetCount
            parts.append("\(count) \(count == 1 ? "snippet" : "snippets")")
        }
        if group.groupCount > 0 {
            let count = group.groupCount
            parts.append("\(count) \(count == 1 ? "group" : "groups")")
        }

        let details = parts.isEmpty
            ? "This group is empty. This cannot be undone."
            : "This also deletes \(parts.joined(separator: " and ")). This cannot be undone."

        withAnimation(.easeOut(duration: 0.14)) {
            deletion = DeleteRequest(
                target: .group(group.id),
                title: "Delete “\(group.name)”?",
                message: details
            )
        }
    }

    private func requestDeletion(of snippet: Snippet) {
        guard !isOverlayPresented else { return }

        withAnimation(.easeOut(duration: 0.14)) {
            deletion = DeleteRequest(
                target: .snippet(snippet.id),
                title: "Delete “\(snippet.displayName)”?",
                message: "This snippet will be removed. This cannot be undone."
            )
        }
    }

    private func confirmDeletion(_ request: DeleteRequest) {
        switch request.target {
        case .group(let groupID):
            guard let group = groups.first(where: { $0.id == groupID }) else {
                dismissDeletion()
                return
            }

            let selectionIsDeleted = selectedGroup.map {
                $0.id == group.id || $0.isDescendant(of: group)
            } ?? false
            let replacementID = group.parent?.id
            let fallbackID = rootGroups.first(where: { $0.id != group.id })?.id

            withAnimation(.easeOut(duration: 0.16)) {
                SnippetStore.delete(group, in: modelContext)

                if selectionIsDeleted {
                    selectedGroupID = replacementID ?? fallbackID
                }

                deletion = nil
            }

        case .snippet(let snippetID):
            guard let snippet = findSnippet(withID: snippetID) else {
                dismissDeletion()
                return
            }

            withAnimation(.easeOut(duration: 0.16)) {
                SnippetStore.delete(snippet, in: modelContext)
                deletion = nil
            }
        }
    }

    // MARK: - Moving

    private func performMove(_ dragged: DraggedItem, _ target: DragTarget) {
        switch (dragged, target.kind) {
        case (.group(let group), .group):
            guard let targetGroup = groups.first(where: { $0.id == target.id }) else { return }

            let success: Bool
            let destinationGroup: SnippetGroup?

            switch target.zone {
            case .inside:
                success = SnippetStore.moveGroup(group, into: targetGroup, in: modelContext)
                destinationGroup = targetGroup

            case .before, .after:
                success = SnippetStore.moveGroup(
                    group,
                    near: targetGroup,
                    position: target.zone == .before ? .before : .after,
                    in: modelContext
                )
                destinationGroup = targetGroup.parent
            }

            guard success else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                if let destinationGroup {
                    expandPath(of: destinationGroup)
                }
                expandAncestors(of: group)

                if let selectedGroup {
                    expandPath(of: selectedGroup)
                }
            }

        case (.snippet(let snippet), .group):
            guard target.zone == .inside,
                  let targetGroup = groups.first(where: { $0.id == target.id }) else {
                return
            }

            guard SnippetStore.moveSnippet(snippet, into: targetGroup, in: modelContext) else {
                return
            }

            withAnimation(.easeOut(duration: 0.18)) {
                expandPath(of: targetGroup)
                if !isAllSnippetsSelected {
                    selectedGroupID = targetGroup.id
                }
            }

        case (.snippet(let snippet), .snippet):
            guard let targetSnippet = findSnippet(withID: target.id),
                  let destinationGroup = targetSnippet.group else {
                return
            }

            let position: RelativePosition = target.zone == .before ? .before : .after
            guard SnippetStore.moveSnippet(
                snippet,
                near: targetSnippet,
                position: position,
                in: modelContext
            ) else {
                return
            }

            withAnimation(.easeOut(duration: 0.18)) {
                expandPath(of: destinationGroup)
                if !isAllSnippetsSelected {
                    selectedGroupID = destinationGroup.id
                }
            }

        default:
            return
        }
    }

    private func expandPath(of group: SnippetGroup) {
        expandedGroupIDs.insert(group.id)
        for ancestor in group.ancestry.dropLast() {
            expandedGroupIDs.insert(ancestor.id)
        }
    }

    // MARK: - Selection

    private func selectGroup(_ group: SnippetGroup) {
        isAllSnippetsSelected = false
        selectedGroupID = group.id

        withAnimation(.easeOut(duration: 0.16)) {
            _ = expandedGroupIDs.insert(group.id)
        }

        expandAncestors(of: group)
    }

    private func performInitialSelectionIfNeeded(force: Bool = false) {
        if !force, didPerformInitialSelection {
            return
        }
        didPerformInitialSelection = true

        #if DEBUG
        // Demo screenshots are easier to read with the whole tree expanded.
        if CommandLine.arguments.contains("--demo") {
            expandedGroupIDs = Set(groups.map(\.id))
        }
        #endif

        isAllSnippetsSelected = true
        selectedGroupID = nil
    }

    private func expandAncestors(of group: SnippetGroup) {
        let ancestors = group.ancestry.dropLast()
        guard !ancestors.isEmpty else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            for ancestor in ancestors {
                expandedGroupIDs.insert(ancestor.id)
            }
        }
    }

    // MARK: - Helpers

    private func findSnippet(withID id: UUID) -> Snippet? {
        groups
            .lazy
            .flatMap(\.snippets)
            .first { $0.id == id }
    }
}
