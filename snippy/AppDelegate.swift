//
//  AppDelegate.swift
//  snippy
//

import AppKit
import SwiftData

/// AppKit entry point for Snippy's menu bar and Settings window.
///
/// The SwiftUI `App` only supplies the process lifecycle; the status item,
/// quick menu, global hot key and Settings window are all AppKit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private enum DefaultsKey {
        static let hasLaunched = "snippy.hasLaunched"
    }

    private struct QuickSnippetPayload {
        let content: String
        let isHidden: Bool
    }

    private var statusItem: NSStatusItem?
    private let quickMenu = NSMenu()
    private var settingsWindow: SettingsWindow?

    private var hotKeyObserver: NSObjectProtocol?
    private var workspaceObserver: NSObjectProtocol?

    private var lastExternalApplication: NSRunningApplication?
    private var quickMenuTargetApplication: NSRunningApplication?
    private var isOpeningQuickMenuAtCursor = false
    private var isQuickMenuOpen = false
    private var ignoreHotKeyUntil = Date.distantPast

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        SnippyPreferences.registerDefaults()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SelfTest.runIfRequested() {
            return
        }
        #endif

        setUpMainMenu()
        setUpStatusItem()
        startTrackingFrontmostApplications()
        observeHotKey()
        HotKeyManager.shared.start()

        #if DEBUG
        DemoData.seedIfRequested()
        #endif

        let arguments = CommandLine.arguments
        let firstLaunch = !UserDefaults.standard.bool(forKey: DefaultsKey.hasLaunched)
        UserDefaults.standard.set(true, forKey: DefaultsKey.hasLaunched)

        if arguments.contains("--open-manager") {
            presentSettingsAfterLaunch(tab: .snippets)
        } else if arguments.contains("--open-settings") {
            presentSettingsAfterLaunch(tab: .general)
        } else if firstLaunch {
            presentSettingsAfterLaunch(tab: .general)
        } else if arguments.contains("--snapshot") {
            presentSettingsAfterLaunch(tab: .general)
        }

        #if DEBUG
        scheduleSnapshotIfRequested()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.stop()

        if let hotKeyObserver {
            NotificationCenter.default.removeObserver(hotKeyObserver)
        }

        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentSettings(tab: .general)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Builds the standard app menu shown while Settings is active. The quick
    /// menu is intentionally separate and contains only snippets, Settings and
    /// Quit so it stays fast to scan.
    private func setUpMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem(title: "Snippy", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Snippy")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let aboutItem = NSMenuItem(
            title: "About Snippy",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(openSettingsFromAppMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let editSnippetsItem = NSMenuItem(
            title: "Edit Snippets",
            action: #selector(openSnippetsFromAppMenu),
            keyEquivalent: "e"
        )
        editSnippetsItem.target = self
        appMenu.addItem(editSnippetsItem)
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(
            title: "Hide Snippy",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        hideItem.target = NSApp
        appMenu.addItem(hideItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Snippy",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        windowMenu.addItem(NSMenuItem(
            title: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        windowMenu.addItem(NSMenuItem(
            title: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))

        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = mainMenu
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else { return }

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        button.image = NSImage(
            systemSymbolName: "greaterthanorequalto",
            accessibilityDescription: "Snippy"
        )?.withSymbolConfiguration(symbolConfiguration) ?? NSImage(
            systemSymbolName: "chevron.forward.to.line",
            accessibilityDescription: "Snippy"
        )?.withSymbolConfiguration(symbolConfiguration) ?? NSImage(
            systemSymbolName: "doc.text",
            accessibilityDescription: "Snippy"
        )
        button.image?.isTemplate = true
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Snippets"

        quickMenu.autoenablesItems = false
        quickMenu.delegate = self
        item.menu = quickMenu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === quickMenu else { return }

        if !isOpeningQuickMenuAtCursor {
            quickMenuTargetApplication = currentExternalApplication()
        }

        rebuildQuickMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === quickMenu, !isQuickMenuOpen else { return }

        isQuickMenuOpen = true
        HotKeyManager.shared.suspendForQuickMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === quickMenu, isQuickMenuOpen else { return }

        isQuickMenuOpen = false
        ignoreHotKeyUntil = Date().addingTimeInterval(0.5)
        HotKeyManager.shared.resumeAfterQuickMenu()
    }

    /// Rebuilds the status menu on every open so it always reflects the current
    /// SwiftData order. No editing actions live here; see setUpMainMenu().
    private func rebuildQuickMenu() {
        quickMenu.removeAllItems()

        let context = SnippetStorage.container.mainContext
        let groups = (try? context.fetch(FetchDescriptor<SnippetGroup>())) ?? []
        let rootGroups = SnippetStore.rootGroups(from: groups)

        if rootGroups.isEmpty {
            let emptyItem = NSMenuItem(title: "No snippets yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            quickMenu.addItem(emptyItem)
        } else {
            for group in rootGroups {
                quickMenu.addItem(makeGroupMenuItem(for: group))
            }
        }

        quickMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(openSettingsFromQuickMenu),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.isEnabled = true
        quickMenu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitFromQuickMenu),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.isEnabled = true
        quitItem.image = nil
        quickMenu.addItem(quitItem)
    }

    private func makeGroupMenuItem(for group: SnippetGroup) -> NSMenuItem {
        let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
        item.isEnabled = true

        let submenu = NSMenu(title: group.name)
        submenu.autoenablesItems = false

        let children = group.orderedChildren
        let snippets = group.orderedSnippets

        for child in children {
            submenu.addItem(makeGroupMenuItem(for: child))
        }

        for snippet in snippets {
            let snippetItem = NSMenuItem(
                title: snippet.displayName,
                action: #selector(pasteSnippetFromQuickMenu(_:)),
                keyEquivalent: ""
            )
            snippetItem.target = self
            snippetItem.representedObject = QuickSnippetPayload(
                content: snippet.content,
                isHidden: snippet.isSecret
            )
            snippetItem.isEnabled = !snippet.content.isEmpty
            snippetItem.toolTip = tooltip(for: snippet)

            if snippet.isSecret {
                snippetItem.image = NSImage(
                    systemSymbolName: "lock.fill",
                    accessibilityDescription: "Hidden"
                )
            }
            submenu.addItem(snippetItem)
        }

        if children.isEmpty, snippets.isEmpty {
            let emptyItem = NSMenuItem(title: "Empty group", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            submenu.addItem(emptyItem)
        }

        item.submenu = submenu
        return item
    }

    private func tooltip(for snippet: Snippet) -> String? {
        let text = snippet.previewText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { return nil }
        return text.count > 140 ? String(text.prefix(140)) + "…" : text
    }

    private func currentExternalApplication() -> NSRunningApplication? {
        let currentPID = NSRunningApplication.current.processIdentifier

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           !frontmost.isTerminated,
           frontmost.processIdentifier != currentPID {
            return frontmost
        }

        if let last = lastExternalApplication, !last.isTerminated {
            return last
        }

        return nil
    }

    private func startTrackingFrontmostApplications() {
        lastExternalApplication = {
            guard let frontmost = NSWorkspace.shared.frontmostApplication,
                  frontmost.processIdentifier != NSRunningApplication.current.processIdentifier else {
                return nil
            }
            return frontmost
        }()

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }

            MainActor.assumeIsolated {
                guard application.processIdentifier != NSRunningApplication.current.processIdentifier else {
                    return
                }
                self?.lastExternalApplication = application
            }
        }
    }

    private func observeHotKey() {
        hotKeyObserver = NotificationCenter.default.addObserver(
            forName: .snippyHotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self,
                      !self.isQuickMenuOpen,
                      !self.isOpeningQuickMenuAtCursor,
                      Date() >= self.ignoreHotKeyUntil else {
                    return
                }

                self.showQuickMenuAtCursor()
            }
        }
    }

    /// Opens the native quick menu at the pointer location, used by the global shortcut.
    private func showQuickMenuAtCursor() {
        let mouseLocation = NSEvent.mouseLocation

        // Capture the paste target before Snippy becomes active.
        quickMenuTargetApplication = currentExternalApplication()
        isOpeningQuickMenuAtCursor = true
        defer { isOpeningQuickMenuAtCursor = false }

        rebuildQuickMenu()

        let origin = quickMenuOrigin(near: mouseLocation)
        NSApp.activate(ignoringOtherApps: true)
        quickMenu.popUp(positioning: nil, at: origin, in: nil)
    }

    private func quickMenuOrigin(near mouseLocation: NSPoint) -> NSPoint {
        let size = quickMenu.size
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else {
            return mouseLocation
        }

        let visible = screen.visibleFrame
        var origin = mouseLocation

        if size.width > 0 {
            if origin.x + size.width > visible.maxX {
                origin.x = mouseLocation.x - size.width
            }

            origin.x = min(
                max(origin.x, visible.minX),
                visible.maxX - min(size.width, visible.width)
            )
        }

        if size.height > 0 {
            if origin.y - size.height < visible.minY {
                origin.y = mouseLocation.y + size.height
            }

            origin.y = min(
                max(origin.y, visible.minY + min(size.height, visible.height)),
                visible.maxY
            )
        }

        return origin
    }

    private func presentSettings(tab: SettingsTab) {
        if settingsWindow == nil {
            let actions = SnippetsActions(
                copySnippet: { snippet in
                    guard !snippet.isSecret else { return }
                    SnippetPaster.copy(snippet.content)
                },
                close: { [weak self] in
                    self?.settingsWindow?.close()
                }
            )

            settingsWindow = SettingsWindow(actions: actions)
        }

        settingsWindow?.present(tab: tab)
    }

    private func presentSettingsAfterLaunch(tab: SettingsTab) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                self?.presentSettings(tab: tab)
            }
        }
    }

    @objc
    private func pasteSnippetFromQuickMenu(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? QuickSnippetPayload,
              !payload.content.isEmpty else {
            NSSound.beep()
            return
        }

        if payload.isHidden {
            SnippetPaster.copyAndPaste(
                payload.content,
                targetApplication: quickMenuTargetApplication,
                clearClipboardAfterPaste: true
            )
        } else if SnippyPreferences.pasteAutomatically {
            SnippetPaster.copyAndPaste(payload.content, targetApplication: quickMenuTargetApplication)
        } else {
            SnippetPaster.copy(payload.content)
        }
    }

    @objc
    private func openSettingsFromQuickMenu() {
        // Wait for NSMenu tracking to end; activating the app and ordering the
        // window front during tracking can swallow the first click.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                self?.presentSettings(tab: .general)
            }
        }
    }

    @objc
    private func quitFromQuickMenu() {
        NSApp.terminate(nil)
    }

    @objc
    private func openSettingsFromAppMenu() {
        presentSettings(tab: .general)
    }

    @objc
    private func openSnippetsFromAppMenu() {
        presentSettings(tab: .snippets)
    }

    @objc
    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Snippy",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1",
            .credits: NSAttributedString(
                string: "A small, native home for the text you paste all the time.",
                attributes: [.font: NSFont.systemFont(ofSize: 11)]
            )
        ])
    }

    #if DEBUG
    /// Debug-only helper used by `--snapshot`; release builds omit it.
    private func scheduleSnapshotIfRequested() {
        let arguments = CommandLine.arguments
        guard let flagIndex = arguments.firstIndex(of: "--snapshot"),
              arguments.indices.contains(flagIndex + 1) else {
            return
        }

        let url = URL(fileURLWithPath: arguments[flagIndex + 1])

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            MainActor.assumeIsolated {
                self?.settingsWindow?.saveSnapshot(to: url)
            }
        }
    }
    #endif
}
