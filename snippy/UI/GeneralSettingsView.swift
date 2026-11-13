//
//  GeneralSettingsView.swift
//  snippy
//

import AppKit
import SwiftData
import SwiftUI

/// The General tab: launch at login, paste behavior, backups and permissions.
///
/// Settings are applied immediately; there is no Save button.
struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var hotKey = HotKeyManager.shared
    @AppStorage(SnippyPreferences.pasteAutomaticallyKey) private var pasteAutomatically = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var isSyncingLaunchAtLogin = false
    @State private var accessibilityGranted = AccessibilityPermission.isGranted
    @State private var backupStatus: String?
    @State private var backupStatusIsWarning = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section {
                        Toggle("Launch at login", isOn: $launchAtLogin)
                            .toggleStyle(.checkbox)
                            .onChange(of: launchAtLogin) { _, newValue in
                                updateLaunchAtLogin(newValue)
                            }

                        if let launchAtLoginError {
                            Text(launchAtLoginError)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    divider

                    section(title: "Behavior") {
                        Toggle("Paste automatically after selecting a snippet", isOn: $pasteAutomatically)
                            .toggleStyle(.checkbox)

                        Text("When off, choosing a snippet only copies it to the clipboard.")
                            .settingsCaption()
                    }

                    divider

                    section(title: "Shortcut") {
                        HStack(spacing: 8) {
                            Text("Open quick menu")

                            Spacer(minLength: 8)

                            ShortcutRecorder(shortcut: hotKey.shortcut) { newShortcut in
                                hotKey.update(newShortcut)
                            }

                            Button {
                                hotKey.resetToDefault()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reset to \(SnippyShortcut.defaultShortcut.displayString)")
                        }

                        if let error = hotKey.registrationError {
                            Text(error)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("Click the shortcut and press a new key combination. Default: \(SnippyShortcut.defaultShortcut.displayString).")
                            .settingsCaption()
                    }

                    divider

                    section(title: "Backup") {
                        HStack(spacing: 8) {
                            Button("Export") {
                                exportBackup()
                            }

                            Button("Import") {
                                importBackup()
                            }

                            Spacer()
                        }
                        .controlSize(.small)

                        Text("Export settings and snippets to a JSON file, or restore them from a previous backup. Importing replaces the current data.")
                            .settingsCaption()

                        if let backupStatus {
                            Text(backupStatus)
                                .font(.system(size: 10.5))
                                .foregroundStyle(backupStatusIsWarning ? Color.orange : Color.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    divider

                    section(title: "Permissions") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accessibilityGranted ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)

                            Text(accessibilityGranted
                                 ? "Accessibility access granted"
                                 : "Accessibility access is required for auto-paste")

                            Spacer()

                            Button("Open Settings") {
                                AccessibilityPermission.openSystemSettings()
                            }
                            .controlSize(.small)
                        }

                        Text("Snippy pastes into the active app by sending ⌘V. Grant access in System Settings → Privacy & Security → Accessibility.")
                            .settingsCaption()
                    }

                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 34)
                .padding(.top, 18)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity)
            }

            Text("Snippy \(version)")
                .settingsCaption()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshState()
        }
    }

    // MARK: - Backup

    private func exportBackup() {
        guard let url = SnippetBackupUI.chooseExportURL() else { return }

        do {
            let backup = try SnippetBackup.makeBackup(in: modelContext)
            try SnippetBackup.write(backup, to: url)
            setBackupStatus(
                "Exported \(summary(of: backup.counts)) to \(url.lastPathComponent).",
                isWarning: false
            )
        } catch {
            backupStatus = nil
            SnippetBackupUI.showError(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func importBackup() {
        guard let url = SnippetBackupUI.chooseImportURL() else { return }

        do {
            let backup = try SnippetBackup.read(from: url)
            guard SnippetBackupUI.confirmImport(fileName: url.lastPathComponent, counts: backup.counts) else {
                return
            }

            let result = try SnippetBackup.restore(backup, in: modelContext)
            pasteAutomatically = backup.configuration.pasteAutomatically
            refreshState()
            NotificationCenter.default.post(name: .snippyBackupDidImport, object: nil)

            var status = "Imported \(summary(of: result.counts)) from \(url.lastPathComponent)."
            if let warning = result.warning {
                status += " " + warning
                SnippetBackupUI.showWarning(title: "Launch at Login Not Updated", message: warning)
            }
            setBackupStatus(status, isWarning: result.warning != nil)
        } catch {
            backupStatus = nil
            SnippetBackupUI.showError(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func setBackupStatus(_ text: String, isWarning: Bool) {
        backupStatus = text
        backupStatusIsWarning = isWarning
    }

    private func summary(of counts: SnippetBackupCounts) -> String {
        let groups = "\(counts.groups) \(counts.groups == 1 ? "group" : "groups")"
        let snippets = "\(counts.snippets) \(counts.snippets == 1 ? "snippet" : "snippets")"
        return "\(groups) and \(snippets)"
    }

    /// Applies the toggle through SMAppService only after the user changes it.
    /// A plain `.onChange` (rather than a custom Toggle binding) prevents the
    /// initial SwiftUI reconciliation from registering the app at launch.
    private func updateLaunchAtLogin(_ enabled: Bool) {
        guard !isSyncingLaunchAtLogin else { return }
        guard enabled != LaunchAtLogin.isEnabled else {
            launchAtLoginError = nil
            return
        }

        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginError = nil
        } catch {
            isSyncingLaunchAtLogin = true
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginError = error.localizedDescription

            DispatchQueue.main.async {
                isSyncingLaunchAtLogin = false
            }
        }
    }

    private var divider: some View {
        Divider()
            .padding(.vertical, 14)
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private func section<Content: View>(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            content()
        }
        .font(.system(size: 12.5))
    }

    private func refreshState() {
        launchAtLogin = LaunchAtLogin.isEnabled
        accessibilityGranted = AccessibilityPermission.isGranted
    }
}

private extension Text {
    func settingsCaption() -> some View {
        self
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
