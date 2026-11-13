//
//  EditorOverlay.swift
//  snippy
//

import SwiftUI

/// Identifies which group or snippet the editor is currently editing.
struct EditorState: Identifiable {
    enum Kind {
        case newGroup(parentID: UUID?)
        case renameGroup(groupID: UUID)
        case newSnippet(groupID: UUID)
        case editSnippet(snippetID: UUID)
    }

    let id = UUID()
    let kind: Kind
    let initialName: String
    let initialContent: String
    let contextDescription: String?
    let initialHidden: Bool

    var isSnippet: Bool {
        switch kind {
        case .newSnippet, .editSnippet:
            return true
        case .newGroup, .renameGroup:
            return false
        }
    }

    var isNew: Bool {
        switch kind {
        case .newGroup, .newSnippet:
            return true
        case .renameGroup, .editSnippet:
            return false
        }
    }

    var title: String {
        switch kind {
        case .newGroup:
            return "New Group"
        case .renameGroup:
            return "Rename Group"
        case .newSnippet:
            return "New Snippet"
        case .editSnippet:
            return "Edit Snippet"
        }
    }

    var subtitle: String {
        switch kind {
        case .newGroup:
            return "Groups can hold snippets and other groups."
        case .renameGroup:
            return "Choose a name for this group."
        case .newSnippet:
            return "Click the snippet later to paste it into the active app."
        case .editSnippet:
            return "Update the name or the text."
        }
    }

    var saveLabel: String {
        isNew ? "Create" : "Save"
    }

    var icon: String {
        switch kind {
        case .newGroup:
            return "folder.badge.plus"
        case .renameGroup:
            return "folder"
        case .newSnippet:
            return "doc.badge.plus"
        case .editSnippet:
            return "doc.text"
        }
    }
}

/// Shared create/rename sheet for groups and snippets in the Snippets tab.
struct EditorOverlay: View {
    private enum Field: Hashable {
        case name
        case content
    }

    let state: EditorState
    let onSave: (String, String, Bool) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var content: String
    @State private var isHidden: Bool
    @FocusState private var focusedField: Field?

    init(
        state: EditorState,
        onSave: @escaping (String, String, Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: state.initialName)
        _content = State(initialValue: state.initialContent)
        _isHidden = State(initialValue: state.initialHidden)
    }

    private var canSave: Bool {
        if state.isSnippet {
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* Keep the editor open until it is explicitly dismissed. */ }

            card
                .padding(.horizontal, 28)
                .frame(maxWidth: state.isSnippet ? 540 : 420)
        }
        .transition(.opacity)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .opacity(0.5)

            VStack(alignment: .leading, spacing: 13) {
                fieldLabel("Name")

                TextField(
                    state.isSnippet ? "Optional — the first line is used if empty" : "Group name",
                    text: $name
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 9)
                .frame(height: 31)
                .background(fieldBackground)
                .focused($focusedField, equals: .name)

                if state.isSnippet {
                    fieldLabel("Content")
                        .padding(.top, 2)

                    contentEditor

                    Toggle("Hidden", isOn: $isHidden)
                        .toggleStyle(.checkbox)

                    Text("Hidden snippets are masked in previews, pasted directly, and cleared from the clipboard afterwards.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()
                .opacity(0.5)

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .onAppear {
            focusedField = .name
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: state.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 29, height: 29)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.accentColor.opacity(0.13))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.system(size: 13.5, weight: .semibold))

                Text(state.subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background {
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel")
            .accessibilityLabel("Cancel")
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(0.055))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        focusedField == .name ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.06),
                        lineWidth: 0.8
                    )
            }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private var contentEditor: some View {
        ZStack(alignment: .topLeading) {
            if content.isEmpty {
                Text("Paste or type the text to keep")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $content)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .content)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
        }
        .frame(minHeight: 132, idealHeight: 150, maxHeight: 180)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            focusedField == .content ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.06),
                            lineWidth: 0.8
                        )
                }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let context = state.contextDescription {
                Text(context)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button(state.saveLabel) {
                onSave(name, content, isHidden)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canSave)
        }
    }
}
