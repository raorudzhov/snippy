//
//  SnippetCardView.swift
//  snippy
//

import SwiftUI

/// Callbacks supplied by the Snippets tab to a snippet card.
struct SnippetCardActions {
    var activate: (Snippet) -> Void
    var copy: (Snippet) -> Void
    var delete: (Snippet) -> Void
    var move: (DraggedItem, DragTarget) -> Void
}

/// An editable snippet card with copy/delete actions and drag support.
///
/// Clicking the card opens the editor; the copy and delete controls live in the
/// hover menu and context menu.
struct SnippetCardView: View {
    let snippet: Snippet
    let actions: SnippetCardActions

    @Environment(SnippetDragState.self) private var dragState
    @State private var isHovered = false
    @State private var measuredHeight: CGFloat = 54

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardBody
                .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
                .onTapGesture {
                    actions.activate(snippet)
                }
                .help("Edit “\(snippet.displayName)”")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(snippet.displayName))
                .accessibilityHint(Text("Opens the snippet editor"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    actions.activate(snippet)
                }

            if isHovered {
                HStack(spacing: 3) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                        .allowsHitTesting(false)

                    cardMenu
                }
                .padding(.top, 5)
                .padding(.trailing, 5)
                .transition(.opacity)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(isHovered ? Color.snippetHoverFill : Color.snippetFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.07 : 0.035), lineWidth: 0.7)
        }
        .overlay {
            if let target = dragState.hoverTarget,
               target.kind == .snippet,
               target.id == snippet.id {
                DropIndicator(zone: target.zone)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { measuredHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in
                        measuredHeight = newHeight
                    }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .onDrag {
            dragState.begin(.snippet(snippet))
            return SnippetDragPayload.provider(for: .snippet(snippet))
        }
        .onDrop(
            of: [SnippetDragPayload.typeIdentifier],
            delegate: SnippetDropDelegate(
                snippet: snippet,
                height: measuredHeight,
                dragState: dragState,
                move: actions.move
            )
        )
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .animation(.easeOut(duration: 0.08), value: dragState.hoverTarget)
        .contextMenu {
            Button {
                actions.activate(snippet)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            if !snippet.isSecret {
                Button {
                    actions.copy(snippet)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                actions.delete(snippet)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: snippet.displayName)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 44)
            }

            if snippet.isSecret {
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .medium))

                    Text("Hidden value")
                        .font(.system(size: 11.5))
                }
                .foregroundStyle(.tertiary)
            } else if snippet.previewText.isEmpty {
                Text("Empty snippet")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            } else {
                Text(verbatim: snippet.previewText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }

    private var cardMenu: some View {
        Menu {
            Button {
                actions.activate(snippet)
            } label: {
                Label("Edit", systemImage: "pencil")
            }

            if !snippet.isSecret {
                Button {
                    actions.copy(snippet)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button(role: .destructive) {
                actions.delete(snippet)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 19, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.065))
                }
                .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Snippet actions")
        .accessibilityLabel("Snippet actions")
    }
}
