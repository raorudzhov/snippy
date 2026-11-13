//
//  ShortcutRecorder.swift
//  snippy
//

import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ShortcutRecordingState {
    nonisolated(unsafe) static var isActive = false
}

/// A compact shortcut field that records the next key combination.
struct ShortcutRecorder: View {
    let shortcut: SnippyShortcut
    let onChange: (SnippyShortcut) -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            HStack(spacing: 3) {
                if isRecording {
                    Text("Press keys…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(shortcut.displayComponents.enumerated()), id: \.offset) { _, component in
                        ShortcutKeycap(text: component)
                    }
                }
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isRecording ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.08),
                        lineWidth: isRecording ? 1.2 : 0.7
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Click and press a new key combination")
        .accessibilityLabel("Open quick menu shortcut")
        .accessibilityValue(shortcut.displayString)
        .accessibilityHint("Press to record a new shortcut")
        .onChange(of: isEnabled) { _, enabled in
            if !enabled {
                stopRecording()
            }
        }
        .onChange(of: shortcut) { _, _ in
            stopRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .snippySettingsWindowDidClose)) { _ in
            stopRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard monitor == nil else { return }

        isRecording = true
        ShortcutRecordingState.isActive = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            let modifiers = event.modifierFlags.intersection(SnippyShortcut.relevantModifiers)
            guard !modifiers.isEmpty,
                  let keyLabel = Self.keyLabel(for: event) else {
                NSSound.beep()
                return nil
            }

            let newShortcut = SnippyShortcut(
                keyCode: event.keyCode,
                modifiers: modifiers,
                keyLabel: keyLabel
            )
            stopRecording()
            onChange(newShortcut)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        isRecording = false
        ShortcutRecordingState.isActive = false
    }

    private static func keyLabel(for event: NSEvent) -> String? {
        switch Int(event.keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_ForwardDelete:
            return "⌦"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_UpArrow:
            return "↑"
        case kVK_DownArrow:
            return "↓"
        case kVK_Home:
            return "Home"
        case kVK_End:
            return "End"
        case kVK_PageUp:
            return "Page Up"
        case kVK_PageDown:
            return "Page Down"
        case kVK_F1:
            return "F1"
        case kVK_F2:
            return "F2"
        case kVK_F3:
            return "F3"
        case kVK_F4:
            return "F4"
        case kVK_F5:
            return "F5"
        case kVK_F6:
            return "F6"
        case kVK_F7:
            return "F7"
        case kVK_F8:
            return "F8"
        case kVK_F9:
            return "F9"
        case kVK_F10:
            return "F10"
        case kVK_F11:
            return "F11"
        case kVK_F12:
            return "F12"
        default:
            guard let characters = event.charactersIgnoringModifiers,
                  !characters.isEmpty else {
                return nil
            }

            let label = characters.trimmingCharacters(in: .whitespacesAndNewlines)
            return label.isEmpty ? nil : label.uppercased()
        }
    }
}

private struct ShortcutKeycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.5)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.065))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.7)
            }
    }
}
