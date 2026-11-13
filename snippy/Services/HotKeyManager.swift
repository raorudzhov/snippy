//
//  HotKeyManager.swift
//  snippy
//

import Foundation
import Observation

/// Owns the configurable global shortcut and keeps Carbon registration in sync.
@MainActor
@Observable
final class HotKeyManager {
    static let shared = HotKeyManager()

    private(set) var shortcut: SnippyShortcut
    private(set) var isRegistered = false
    private(set) var registrationError: String?

    private let hotKey = GlobalHotKey()
    private var isStarted = false
    private var isSuspended = false

    private init() {
        shortcut = SnippyPreferences.openShortcut
    }

    func start() {
        isStarted = true
        isSuspended = false
        register()
    }

    func stop() {
        isStarted = false
        isSuspended = false
        hotKey.unregister()
        isRegistered = false
    }

    /// Temporarily unregisters the shortcut while a menu is tracking so repeated
    /// presses cannot pile up and reopen the menu after it closes.
    func suspendForQuickMenu() {
        guard isStarted, !isSuspended else { return }
        isSuspended = true
        hotKey.unregister()
        isRegistered = false
        registrationError = nil
    }

    func resumeAfterQuickMenu() {
        guard isStarted, isSuspended else { return }
        isSuspended = false
        register()
    }

    func update(_ newShortcut: SnippyShortcut) {
        shortcut = newShortcut
        SnippyPreferences.setOpenShortcut(newShortcut)

        guard isStarted, !isSuspended else { return }
        register()
    }

    func resetToDefault() {
        update(.defaultShortcut)
    }

    private func register() {
        hotKey.unregister()

        let success = hotKey.register(shortcut)
        isRegistered = success
        registrationError = success
            ? nil
            : "This shortcut is already in use. Choose another combination."
    }
}
