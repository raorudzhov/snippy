import AppKit
import Carbon.HIToolbox
import OSLog

/// Pasteboard helpers and the optional synthetic ⌘V hand-off.
///
/// Auto-paste is best-effort: without Accessibility access the snippet is still
/// copied, and the caller can ask the user to grant permission.
@MainActor
enum SnippetPaster {
    /// Standard hints used by clipboard managers to skip sensitive content.
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func copy(_ text: String, concealed: Bool = false) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if concealed {
            pasteboard.setString("", forType: Self.concealedType)
            pasteboard.setString("", forType: Self.transientType)
        }

        pasteboard.setString(text, forType: .string)
    }

    static func paste(into targetApplication: NSRunningApplication?) {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.requestIfNeeded()
            return
        }

        let currentPID = NSRunningApplication.current.processIdentifier

        if NSApp.isActive {
            guard let targetApplication,
                  !targetApplication.isTerminated,
                  targetApplication.processIdentifier != currentPID else {
                return
            }

            targetApplication.activate(options: [.activateAllWindows])

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))

                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetApplication.processIdentifier else {
                    return
                }

                postPasteKeystroke()
            }
            return
        }

        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != currentPID else {
            return
        }

        postPasteKeystroke()
    }

    /// Copies the text and schedules the paste after the quick menu has closed.
    static func copyAndPaste(
        _ text: String,
        targetApplication: NSRunningApplication?,
        after delay: TimeInterval = 0.12,
        clearClipboardAfterPaste: Bool = false
    ) {
        copy(text, concealed: clearClipboardAfterPaste)

        if clearClipboardAfterPaste {
            clearClipboard(matching: text, after: delay + 0.7)
        }

        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.requestIfNeeded()
            return
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))
            paste(into: targetApplication)
        }
    }

    private static func clearClipboard(matching text: String, after delay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1_000)))

            let pasteboard = NSPasteboard.general
            guard pasteboard.string(forType: .string) == text else { return }
            pasteboard.clearContents()
            AppLog.paste.debug("Cleared hidden clipboard content")
        }
    }

    private static func postPasteKeystroke() {
        guard AccessibilityPermission.isGranted else { return }

        let source = CGEventSource(stateID: .combinedSessionState)
        // Avoid our own keyboard events being interpreted while the shortcut is
        // being synthesized (the same approach Maccy uses).
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyCode = CGKeyCode(kVK_ANSI_V)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)

        AppLog.paste.debug("Posted paste keystroke")
    }
}
