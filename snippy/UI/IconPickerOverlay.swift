//
//  IconPickerOverlay.swift
//  snippy
//

import AppKit
import SwiftUI

struct IconPickerState: Identifiable {
    let id = UUID()
    let groupID: UUID
    let groupName: String
    let initialSymbol: String
}

/// SF Symbols picker for a folder icon.
struct IconPickerOverlay: View {
    let state: IconPickerState
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var query = ""
    @State private var selection: String
    @FocusState private var isSearchFocused: Bool

    init(
        state: IconPickerState,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.onSave = onSave
        self.onCancel = onCancel
        _selection = State(initialValue: state.initialSymbol)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* Keep the picker open until Done or Escape. */ }

            card
                .frame(width: 520, height: 460)
                .padding(.horizontal, 28)
        }
        .transition(.opacity)
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()
                .opacity(0.5)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    ForEach(visibleGroups) { group in
                        symbolSection(group)
                    }

                    if visibleGroups.isEmpty {
                        noResults
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .onAppear {
            isSearchFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: selection)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: 29, height: 29)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentColor.opacity(0.13))
                    }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Customize Icon")
                        .font(.system(size: 13.5, weight: .semibold))

                    Text(state.groupName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background {
                            Circle()
                                .fill(Color.primary.opacity(0.06))
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Cancel")

                Button("Done") {
                    onSave(selection)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search or enter any SF Symbols name", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isSearchFocused)
                    .onSubmit {
                        let trimmed = trimmedQuery
                        if !trimmed.isEmpty, Self.isAvailableSymbol(trimmed) {
                            selection = trimmed
                        }
                    }

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
        }
    }

    private func symbolSection(_ group: SymbolGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(group.title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 30, maximum: 30), spacing: 6)],
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(group.symbols, id: \.self) { symbol in
                    SymbolChoice(
                        symbol: symbol,
                        isSelected: selection == symbol
                    ) {
                        selection = symbol
                    }
                }
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: 5) {
            Text("No symbols found")
                .font(.system(size: 12, weight: .medium))

            Text("Pick an icon from the list or enter a valid SF Symbols name.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleGroups: [SymbolGroup] {
        let term = trimmedQuery
        guard !term.isEmpty else {
            let groups = Self.availableCatalog
            guard Self.isAvailableSymbol(selection),
                  !groups.contains(where: { $0.symbols.contains(selection) }) else {
                return groups
            }
            return [SymbolGroup(title: "Current", symbols: [selection])] + groups
        }

        var groups = Self.availableCatalog.compactMap { group -> SymbolGroup? in
            let symbols = group.symbols.filter { $0.localizedCaseInsensitiveContains(term) }
            return symbols.isEmpty ? nil : SymbolGroup(title: group.title, symbols: symbols)
        }

        if Self.isAvailableSymbol(term),
           !groups.contains(where: { $0.symbols.contains(term) }) {
            groups.insert(SymbolGroup(title: "Entered Symbol", symbols: [term]), at: 0)
        }

        return groups
    }

    nonisolated private static func isAvailableSymbol(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    private static let availableCatalog: [SymbolGroup] = catalog
        .map { group in
            SymbolGroup(
                title: group.title,
                symbols: group.symbols.filter(isAvailableSymbol)
            )
        }
        .filter { !$0.symbols.isEmpty }

    private static let catalog: [SymbolGroup] = [
        SymbolGroup(
            title: "Default",
            symbols: [
                "folder", "folder.fill", "tray", "tray.full", "archivebox",
                "briefcase", "doc.on.doc", "star", "heart"
            ]
        ),
        SymbolGroup(
            title: "Objects & Tools",
            symbols: [
                "doc.text", "doc.richtext", "doc.plaintext", "doc.on.clipboard", "clipboard",
                "note.text", "book", "book.closed", "bookmark", "tag", "paperclip", "link",
                "terminal", "curlybraces", "chevron.left.forwardslash.chevron.right",
                "keyboard", "gearshape", "wrench.and.screwdriver", "hammer", "paintpalette",
                "paintbrush", "scissors", "ruler", "pencil", "highlighter", "eraser",
                "textformat", "list.bullet", "checklist", "square.grid.2x2", "tablecells",
                "qrcode", "barcode", "signature", "printer", "scanner", "externaldrive",
                "internaldrive", "server.rack", "memorychip", "cpu", "opticaldisc", "sdcard",
                "usb", "cable.connector", "powerplug", "lightbulb", "flashlight.on",
                "wand.and.stars", "puzzlepiece", "cube", "shippingbox", "calendar", "clock",
                "alarm", "timer", "hourglass", "chart.bar", "chart.pie", "function",
                "percent", "dollarsign", "eurosign", "rublesign", "bitcoinsign", "key",
                "lock", "shield", "eye", "magnifyingglass"
            ]
        ),
        SymbolGroup(
            title: "Communication",
            symbols: [
                "envelope", "envelope.open", "paperplane", "bubble.left", "bubble.right",
                "message", "phone", "person", "person.2", "person.crop.circle",
                "hand.raised", "hand.thumbsup", "hand.thumbsdown", "at", "number",
                "bell", "megaphone"
            ]
        ),
        SymbolGroup(
            title: "Media & Nature",
            symbols: [
                "camera", "photo", "video", "film", "music.note", "headphones",
                "speaker.wave.2", "mic", "play", "pause", "stop", "forward", "backward",
                "shuffle", "repeat", "star.fill", "sparkles", "bolt", "flame", "leaf",
                "sun.max", "moon", "cloud", "cloud.sun", "umbrella", "drop", "snowflake",
                "wind", "tornado", "rainbow", "globe", "map", "location", "flag", "crown",
                "trophy", "gift", "cart", "bag", "creditcard", "gamecontroller",
                "die.face.5", "party.popper", "balloon"
            ]
        ),
        SymbolGroup(
            title: "Places & Devices",
            symbols: [
                "house", "building", "building.2", "car", "airplane", "ferry", "bicycle",
                "figure.walk", "figure.run", "bus", "fuelpump", "display",
                "desktopcomputer", "laptopcomputer", "iphone", "ipad", "applewatch",
                "mouse", "airpods", "homekit", "wifi", "antenna.radiowaves.left.and.right",
                "network"
            ]
        )
    ]
}

private struct SymbolGroup: Identifiable {
    let title: String
    let symbols: [String]

    var id: String { title }
}

private struct SymbolChoice: View {
    let symbol: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 30, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor
                                : (isHovered ? Color.primary.opacity(0.07) : Color.clear)
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(symbol)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
