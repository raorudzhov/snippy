//
//  SnippyPreferences.swift
//  snippy
//

import AppKit
import Foundation

/// UserDefaults keys shared by the Settings UI and the quick menu.
enum SnippyPreferences {
    static let pasteAutomaticallyKey = "snippy.pasteAutomatically"
    static let openShortcutKeyCodeKey = "snippy.openShortcut.keyCode"
    static let openShortcutModifiersKey = "snippy.openShortcut.modifiers"
    static let openShortcutKeyLabelKey = "snippy.openShortcut.keyLabel"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            pasteAutomaticallyKey: true,
            openShortcutKeyCodeKey: Int(SnippyShortcut.defaultShortcut.keyCode),
            openShortcutModifiersKey: Int(SnippyShortcut.defaultShortcut.modifiers.rawValue),
            openShortcutKeyLabelKey: SnippyShortcut.defaultShortcut.keyLabel
        ])
    }

    static var pasteAutomatically: Bool {
        UserDefaults.standard.bool(forKey: pasteAutomaticallyKey)
    }

    static var openShortcut: SnippyShortcut {
        let defaults = UserDefaults.standard
        let rawKeyCode = defaults.integer(forKey: openShortcutKeyCodeKey)
        let label = (defaults.string(forKey: openShortcutKeyLabelKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawModifiers = defaults.integer(forKey: openShortcutModifiersKey)
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(max(0, rawModifiers)))
            .intersection(SnippyShortcut.relevantModifiers)

        guard rawKeyCode >= 0,
              rawKeyCode <= Int(UInt16.max),
              !label.isEmpty,
              !modifiers.isEmpty else {
            return .defaultShortcut
        }

        return SnippyShortcut(
            keyCode: UInt16(rawKeyCode),
            modifiers: modifiers,
            keyLabel: label
        )
    }

    static func setOpenShortcut(_ shortcut: SnippyShortcut) {
        let defaults = UserDefaults.standard
        defaults.set(Int(shortcut.keyCode), forKey: openShortcutKeyCodeKey)
        defaults.set(Int(shortcut.modifiers.rawValue), forKey: openShortcutModifiersKey)
        defaults.set(shortcut.keyLabel, forKey: openShortcutKeyLabelKey)
    }
}
