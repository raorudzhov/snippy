//
//  DragAndDrop.swift
//  snippy
//

import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The two kinds of model objects that can participate in a drag.
enum DragItemKind {
    case group
    case snippet
}

/// A type-safe drag payload. SwiftUI's drop delegates receive it through the
/// shared `SnippetDragState`; the pasteboard string is only a fallback.
enum DraggedItem {
    case group(SnippetGroup)
    case snippet(Snippet)

    var id: UUID {
        switch self {
        case .group(let group):
            return group.id
        case .snippet(let snippet):
            return snippet.id
        }
    }

    var kind: DragItemKind {
        switch self {
        case .group:
            return .group
        case .snippet:
            return .snippet
        }
    }

    var payloadString: String {
        switch self {
        case .group(let group):
            return "group:\(group.id.uuidString)"
        case .snippet(let snippet):
            return "snippet:\(snippet.id.uuidString)"
        }
    }
}

/// Whether the dragged item should be inserted before or after the target row.
enum DropZone: Equatable {
    case before
    case inside
    case after
}

/// The model type represented by a drop target.
enum DragTargetKind: Equatable {
    case group
    case snippet
}

/// A drop destination: the row under the pointer and the insertion zone.
struct DragTarget: Equatable {
    let kind: DragTargetKind
    let id: UUID
    let zone: DropZone
}

/// Per-window drag state shared by every draggable row and drop delegate.
@MainActor
@Observable
final class SnippetDragState {
    var draggedItem: DraggedItem?
    var hoverTarget: DragTarget?

    func begin(_ item: DraggedItem) {
        draggedItem = item
        hoverTarget = nil
    }

    func end() {
        draggedItem = nil
        hoverTarget = nil
    }
}

/// Builds the NSItemProvider used by SwiftUI's drag source.
///
/// The item itself travels through `SnippetDragState`; the plain-text payload
/// exists so the drag has a standard UTI that drop destinations accept.
enum SnippetDragPayload {
    /// Use a standard text UTI: private custom UTIs are not reliably matched by
    /// SwiftUI's drop destinations unless they are declared in the Info.plist.
    /// The drag state still provides the typed item; the string is a fallback.
    static let typeIdentifier = UTType.utf8PlainText.identifier

    static func provider(for item: DraggedItem) -> NSItemProvider {
        NSItemProvider(object: item.payloadString as NSString)
    }
}

/// Accepts group and snippet drags on a group row. The middle of the row means
/// "move inside"; the top and bottom edges mean "insert before/after".
struct GroupDropDelegate: DropDelegate {
    let group: SnippetGroup
    let height: CGFloat
    let dragState: SnippetDragState
    let move: (DraggedItem, DragTarget) -> Void

    func dropEntered(info: DropInfo) {
        _ = update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info) ? DropProposal(operation: .move) : DropProposal(operation: .cancel)
    }

    func dropExited(info: DropInfo) {
        clearHoverIfOwned()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = dragState.draggedItem,
              let target = dragState.hoverTarget,
              target.kind == .group,
              target.id == group.id else {
            return false
        }

        move(dragged, target)
        dragState.end()
        return true
    }

    private func update(_ info: DropInfo) -> Bool {
        guard let dragged = dragState.draggedItem else {
            clearHoverIfOwned()
            return false
        }

        let zone = dropZone(for: dragged, y: info.location.y)
        guard canDrop(dragged, zone: zone) else {
            clearHoverIfOwned()
            return false
        }

        let target = DragTarget(kind: .group, id: group.id, zone: zone)
        if dragState.hoverTarget != target {
            dragState.hoverTarget = target
        }

        return true
    }

    private func dropZone(for dragged: DraggedItem, y: CGFloat) -> DropZone {
        if case .snippet = dragged {
            return .inside
        }

        let ratio = min(max(y / max(height, 1), 0), 1)
        if ratio < 0.28 {
            return .before
        }
        if ratio > 0.72 {
            return .after
        }
        return .inside
    }

    private func canDrop(_ dragged: DraggedItem, zone: DropZone) -> Bool {
        switch dragged {
        case .snippet:
            return true

        case .group(let draggedGroup):
            guard group.id != draggedGroup.id else {
                return false
            }

            switch zone {
            case .inside:
                return !group.isDescendant(of: draggedGroup)
            case .before, .after:
                guard let parent = group.parent else {
                    return true
                }
                return parent.id != draggedGroup.id && !parent.isDescendant(of: draggedGroup)
            }
        }
    }

    private func clearHoverIfOwned() {
        guard dragState.hoverTarget?.kind == .group,
              dragState.hoverTarget?.id == group.id else {
            return
        }
        dragState.hoverTarget = nil
    }
}

/// Accepts snippet drags on a snippet row and inserts before or after it.
struct SnippetDropDelegate: DropDelegate {
    let snippet: Snippet
    let height: CGFloat
    let dragState: SnippetDragState
    let move: (DraggedItem, DragTarget) -> Void

    func dropEntered(info: DropInfo) {
        _ = update(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info) ? DropProposal(operation: .move) : DropProposal(operation: .cancel)
    }

    func dropExited(info: DropInfo) {
        clearHoverIfOwned()
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = dragState.draggedItem,
              let target = dragState.hoverTarget,
              target.kind == .snippet,
              target.id == snippet.id else {
            return false
        }

        move(dragged, target)
        dragState.end()
        return true
    }

    private func update(_ info: DropInfo) -> Bool {
        guard case .snippet(let draggedSnippet) = dragState.draggedItem,
              draggedSnippet.id != snippet.id,
              snippet.group != nil else {
            clearHoverIfOwned()
            return false
        }

        let ratio = min(max(info.location.y / max(height, 1), 0), 1)
        let zone: DropZone = ratio < 0.5 ? .before : .after
        let target = DragTarget(kind: .snippet, id: snippet.id, zone: zone)

        if dragState.hoverTarget != target {
            dragState.hoverTarget = target
        }

        return true
    }

    private func clearHoverIfOwned() {
        guard dragState.hoverTarget?.kind == .snippet,
              dragState.hoverTarget?.id == snippet.id else {
            return
        }
        dragState.hoverTarget = nil
    }
}

/// Draws the insertion line or "move inside" highlight for the current target.
struct DropIndicator: View {
    let zone: DropZone

    var body: some View {
        switch zone {
        case .inside:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1.5)
                }
                .allowsHitTesting(false)

        case .before, .after:
            VStack(spacing: 0) {
                if zone == .after {
                    Spacer(minLength: 0)
                }

                InsertionLine()

                if zone == .before {
                    Spacer(minLength: 0)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

private struct InsertionLine: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
        }
        .padding(.horizontal, 6)
    }
}
