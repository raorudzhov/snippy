//
//  GlobalHotKey.swift
//  snippy
//

import Carbon.HIToolbox
import Foundation
import OSLog

extension Notification.Name {
    /// Posted when the system-wide snippet shortcut is pressed.
    static let snippyHotKeyPressed = Notification.Name("raorudzhov.snippy.hotKeyPressed")
}

/// A tiny wrapper around Carbon's global hot key API.
///
/// Unlike event taps, `RegisterEventHotKey` does not require Accessibility
/// permission, so the quick menu can be opened even before the user grants it.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    @discardableResult
    func register(_ shortcut: SnippyShortcut) -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            snippyHotKeyEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard handlerStatus == noErr else {
            AppLog.hotKey.error("Could not install the global hot key handler (\(handlerStatus))")
            return false
        }

        let identifier = EventHotKeyID(signature: OSType(0x534E4950), id: 1) // 'SNIP'
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            AppLog.hotKey.error(
                "Could not register \(shortcut.displayString, privacy: .public) (\(status)). It may already be in use."
            )
            unregister()
            return false
        }

        return true
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

nonisolated private func snippyHotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .snippyHotKeyPressed, object: nil)
    }

    return noErr
}
