//
//  SettingsWindow.swift
//  snippy
//

import AppKit
import Observation
import OSLog
import SwiftData
import SwiftUI

extension Notification.Name {
    /// Posted by the Settings window; the Snippets tab uses it for lifecycle
    /// work and for the Escape-to-close flow.
    static let snippyEscapePressed = Notification.Name("raorudzhov.snippy.escapePressed")
    static let snippySettingsWindowDidShow = Notification.Name("raorudzhov.snippy.settingsWindowDidShow")
    static let snippySettingsWindowDidClose = Notification.Name("raorudzhov.snippy.settingsWindowDidClose")
    static let snippyBackupDidImport = Notification.Name("raorudzhov.snippy.backupDidImport")
}

/// Actions that the Snippets tab needs from the app delegate.
struct SnippetsActions {
    var copySnippet: (Snippet) -> Void
    var close: () -> Void
}

/// The two panes of the Settings window. Each pane has its own preferred
/// content size because the editor needs much more room than General.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case snippets

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .snippets:
            return "Snippets"
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "gearshape"
        case .snippets:
            return "text.alignleft"
        }
    }

    var contentSize: NSSize {
        switch self {
        case .general:
            return NSSize(width: 560, height: 560)
        case .snippets:
            return NSSize(width: 900, height: 640)
        }
    }
}

/// Observable selection shared by the window and the SwiftUI tab bar.
@MainActor
@Observable
final class SettingsState {
    var tab: SettingsTab = .general
}

/// A single tabbed preferences window with General and Snippets panes.
@MainActor
final class SettingsWindow: NSWindow, NSWindowDelegate {
    private let state = SettingsState()
    private var escapeMonitor: Any?

    init(actions: SnippetsActions) {
        super.init(
            contentRect: NSRect(origin: .zero, size: SettingsTab.general.contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = SettingsTab.general.title
        titleVisibility = .visible
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        // One solid background for the titlebar, tab strip and both panes.
        backgroundColor = .windowBackgroundColor
        isOpaque = true
        hasShadow = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        isRestorable = false

        delegate = self
        standardWindowButton(.zoomButton)?.isEnabled = false

        let root = SettingsRootView(
            state: state,
            actions: actions,
            onSelectTab: { [weak self] tab in
                self?.apply(tab: tab, resize: true, keepTopLeft: true)
            }
        )
        .modelContainer(SnippetStorage.container)

        let container = SettingsContentView(frame: NSRect(origin: .zero, size: SettingsTab.general.contentSize))
        container.autoresizingMask = [.width, .height]
        contentView = container

        let hostingView = NSHostingView(rootView: root)
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        hostingView.sizingOptions = []
        container.addSubview(hostingView)
    }

    func present(tab: SettingsTab) {
        state.tab = tab

        if isVisible {
            apply(tab: tab, resize: true, keepTopLeft: true)
        } else {
            apply(tab: tab, resize: true, keepTopLeft: false)
            center()
        }

        if isMiniaturized {
            deminiaturize(nil)
        }

        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()

        // Avoid choosing a tree chevron as the first focus target when the
        // Snippets tab happens to be on top.
        if let contentView {
            makeFirstResponder(contentView)
        }
    }

    override func becomeKey() {
        super.becomeKey()
        installEscapeMonitor()
        NotificationCenter.default.post(name: .snippySettingsWindowDidShow, object: nil)
    }

    override func resignKey() {
        super.resignKey()
        removeEscapeMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        removeEscapeMonitor()
        NotificationCenter.default.post(name: .snippySettingsWindowDidClose, object: nil)
    }

    private func apply(tab: SettingsTab, resize: Bool, keepTopLeft: Bool) {
        title = tab.title

        guard resize else { return }

        let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
        setContentSize(tab.contentSize)

        if keepTopLeft {
            setFrameTopLeftPoint(topLeft)
            clampToScreen()
        }
    }

    private func clampToScreen() {
        guard let screen = screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var origin = frame.origin

        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        setFrameOrigin(origin)
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self != nil,
                  event.keyCode == 53,
                  NSApp.modalWindow == nil,
                  !ShortcutRecordingState.isActive else {
                return event
            }

            NotificationCenter.default.post(name: .snippyEscapePressed, object: nil)
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    #if DEBUG
    /// Renders the settings window into a PNG for headless visual checks.
    func saveSnapshot(to url: URL) {
        guard let contentView else { return }

        let captureView = contentView.superview ?? contentView
        let bounds = captureView.bounds
        guard let representation = captureView.bitmapImageRepForCachingDisplay(in: bounds) else {
            AppLog.settings.error("Could not create a snapshot bitmap")
            return
        }

        captureView.cacheDisplay(in: bounds, to: representation)

        guard let data = representation.representation(using: .png, properties: [:]) else {
            AppLog.settings.error("Could not encode the snapshot")
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url)
            AppLog.settings.info("Saved settings snapshot to \(url.path, privacy: .public)")
        } catch {
            AppLog.settings.error("Could not write the snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif
}

/// Hosts the shared tab bar and keeps both panes alive so their state survives
/// tab switches.
private struct SettingsRootView: View {
    @Bindable var state: SettingsState
    let actions: SnippetsActions
    let onSelectTab: (SettingsTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Reserve room for the transparent titlebar and traffic lights.
            Color.clear
                .frame(height: 30)

            SettingsTabBar(selection: state.tab) { tab in
                guard state.tab != tab else { return }
                state.tab = tab
                onSelectTab(tab)
            }

            Divider()
                .opacity(0.55)

            // Keep both panes alive so switching tabs does not discard editor
            // state or the selected group.
            ZStack {
                GeneralSettingsView()
                    .opacity(state.tab == .general ? 1 : 0)
                    .allowsHitTesting(state.tab == .general)
                    .disabled(state.tab != .general)
                    .accessibilityHidden(state.tab != .general)

                SnippetsView(actions: actions)
                    .opacity(state.tab == .snippets ? 1 : 0)
                    .allowsHitTesting(state.tab == .snippets)
                    .disabled(state.tab != .snippets)
                    .accessibilityHidden(state.tab != .snippets)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }
}

/// A compact, Maccy-inspired icon-and-label tab strip.
private struct SettingsTabBar: View {
    let selection: SettingsTab
    let onSelect: (SettingsTab) -> Void

    var body: some View {
        HStack(spacing: 24) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    onSelect(tab)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .regular))

                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : .secondary)
                    .frame(width: 78, height: 46)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selection == tab ? Color.accentColor.opacity(0.08) : .clear)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}


/// A fixed-size host container. It prevents NSHostingView's ideal size from
/// fighting the per-tab window size.
private final class SettingsContentView: NSView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override var fittingSize: NSSize {
        bounds.size
    }
}
