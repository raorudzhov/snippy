//
//  SnippetBackupUI.swift
//  snippy
//

import AppKit
import UniformTypeIdentifiers

/// AppKit panels and alerts used by the Backup section in General settings.
@MainActor
enum SnippetBackupUI {
    static func chooseExportURL() -> URL? {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "Export Configuration and Snippets"
        panel.message = "Choose where to save the JSON backup."
        panel.prompt = "Export"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func chooseImportURL() -> URL? {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Import Configuration and Snippets"
        panel.message = "Choose a Snippy JSON backup."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func confirmImport(fileName: String, counts: SnippetBackupCounts) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace snippets and settings?"
        alert.informativeText = "Importing “\(fileName)” will replace all current snippets and settings with \(summary(counts)). This cannot be undone."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Import")
        alert.buttons.last?.hasDestructiveAction = true

        return alert.runModal() == .alertSecondButtonReturn
    }

    static func showError(title: String, message: String) {
        presentAlert(title: title, message: message, style: .critical)
    }

    static func showWarning(title: String, message: String) {
        presentAlert(title: title, message: message, style: .warning)
    }

    private static func presentAlert(title: String, message: String, style: NSAlert.Style) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func summary(_ counts: SnippetBackupCounts) -> String {
        let groups = "\(counts.groups) \(counts.groups == 1 ? "group" : "groups")"
        let snippets = "\(counts.snippets) \(counts.snippets == 1 ? "snippet" : "snippets")"
        return "\(groups) and \(snippets)"
    }

    private static var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Snippy Backup \(formatter.string(from: .now)).json"
    }
}
