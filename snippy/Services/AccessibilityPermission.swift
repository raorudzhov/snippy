import AppKit
import ApplicationServices

/// Checks and requests the macOS Accessibility permission required to post
/// synthetic keystrokes (⌘V) into other applications.
@MainActor
enum AccessibilityPermission {
    private static let promptKey = "snippy.didPromptForAccessibility"

    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func request(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func requestIfNeeded() {
        guard !isGranted else { return }
        guard !UserDefaults.standard.bool(forKey: promptKey) else { return }

        UserDefaults.standard.set(true, forKey: promptKey)
        request()
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
