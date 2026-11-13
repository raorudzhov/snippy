//
//  Theme.swift
//  snippy
//

import SwiftUI

/// Shared layout and color tokens for the Snippets editor.
enum Theme {

    static let sidebarWidth: CGFloat = 196
    static let sidebarMinWidth: CGFloat = 150
    static let sidebarMaxWidth: CGFloat = 360
    static let treeRowHeight: CGFloat = 27
    static let cardCornerRadius: CGFloat = 10

    static let horizontalPadding: CGFloat = 14
}

extension Color {
    /// A very light wash used for cards and hovered rows on the window background.
    static var snippetFill: Color {
        Color.primary.opacity(0.045)
    }

    static var snippetHoverFill: Color {
        Color.primary.opacity(0.085)
    }

    static var sidebarFill: Color {
        Color.primary.opacity(0.028)
    }
}
