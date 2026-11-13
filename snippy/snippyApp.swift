//
//  snippyApp.swift
//  snippy
//

import SwiftUI

@main
struct SnippyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var isMenuBarExtraInserted = false

    var body: some Scene {
        // The real menu bar item is an AppKit NSStatusItem created by
        // AppDelegate. This empty, never-inserted scene only satisfies the
        // SwiftUI App lifecycle without adding a second status item.
        MenuBarExtra("Snippy", isInserted: $isMenuBarExtraInserted) {
            EmptyView()
        }
    }
}
