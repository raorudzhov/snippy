//
//  SidebarResizeHandle.swift
//  snippy
//

import AppKit
import SwiftUI

/// A draggable divider that changes the sidebar width.
struct SidebarResizeHandle: View {
    @Binding var width: Double
    let minimumWidth: CGFloat
    let maximumWidth: CGFloat
    let defaultWidth: CGFloat

    @State private var dragStartWidth: CGFloat?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(isHovering ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.12))
                .frame(width: isHovering ? 2 : 1)
        }
        .frame(width: 9)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.resizeLeftRight.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStartWidth == nil {
                        dragStartWidth = clamped(CGFloat(width))
                    }
                    guard let dragStartWidth else { return }
                    width = Double(clamped(dragStartWidth + value.translation.width))
                }
                .onEnded { _ in
                    width = Double(clamped(CGFloat(width)))
                    dragStartWidth = nil
                }
        )
        .onTapGesture(count: 2) {
            width = Double(defaultWidth)
        }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("Drag to resize. Double-click to reset.")
        .accessibilityElement()
        .accessibilityLabel("Resize sidebar")
        .accessibilityValue("\(Int(clamped(CGFloat(width)))) points")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                width = Double(clamped(CGFloat(width) + 16))
            case .decrement:
                width = Double(clamped(CGFloat(width) - 16))
            @unknown default:
                break
            }
        }
    }

    private func clamped(_ width: CGFloat) -> CGFloat {
        let target = width.isFinite ? width : defaultWidth
        return min(max(target, minimumWidth), maximumWidth)
    }
}
