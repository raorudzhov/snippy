//
//  SnippyShortcut.swift
//  snippy
//

import AppKit
import Carbon.HIToolbox

/// A user-recordable global shortcut.
struct SnippyShortcut: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var keyLabel: String

    static let defaultShortcut = SnippyShortcut(
        keyCode: UInt16(kVK_ANSI_X),
        modifiers: [.command, .shift],
        keyLabel: "X"
    )

    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    var displayComponents: [String] {
        var components: [String] = []

        if modifiers.contains(.control) {
            components.append("⌃")
        }
        if modifiers.contains(.option) {
            components.append("⌥")
        }
        if modifiers.contains(.shift) {
            components.append("⇧")
        }
        if modifiers.contains(.command) {
            components.append("⌘")
        }

        components.append(keyLabel)
        return components
    }

    var displayString: String {
        displayComponents.joined()
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0

        if modifiers.contains(.command) {
            value |= UInt32(cmdKey)
        }
        if modifiers.contains(.shift) {
            value |= UInt32(shiftKey)
        }
        if modifiers.contains(.option) {
            value |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            value |= UInt32(controlKey)
        }

        return value
    }
}
