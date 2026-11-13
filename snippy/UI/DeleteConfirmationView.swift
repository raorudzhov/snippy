//
//  DeleteConfirmationView.swift
//  snippy
//

import SwiftUI

/// A destructive action awaiting confirmation in the Snippets tab.
struct DeleteRequest: Identifiable {
    enum Target {
        case group(UUID)
        case snippet(UUID)
    }

    let id = UUID()
    let target: Target
    let title: String
    let message: String
}

/// Modal confirmation card used before deleting a group or snippet.
struct DeleteConfirmationView: View {
    let request: DeleteRequest
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { /* Explicit dismissal only. */ }

            card
                .frame(maxWidth: 360)
                .padding(.horizontal, 28)
        }
        .transition(.opacity)
    }

    private var card: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                    .background {
                        Circle()
                            .fill(Color.red.opacity(0.1))
                    }

                Text(request.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(request.message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 16)

            Divider()
                .opacity(0.5)

            HStack(spacing: 8) {
                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }
}
