//
//  WelcomeView.swift
//  snippy
//

import SwiftUI

/// First-run empty state shown when there are no groups yet.
struct WelcomeView: View {
    let onCreateGroup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 18)

            VStack(spacing: 13) {
                VStack(spacing: 4) {
                    Text("Welcome to Snippy")
                        .font(.system(size: 20, weight: .semibold))

                    Text("A small, native home for the text you paste all the time.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 310)
                }

                Button("Create a Group", action: onCreateGroup)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 2)
            }

            Spacer(minLength: 22)

            VStack(alignment: .leading, spacing: 9) {
                feature(
                    icon: "folder",
                    title: "Organize",
                    text: "Nest groups inside groups as deep as you need."
                )
                feature(
                    icon: "cursorarrow.click",
                    title: "Paste from the menu",
                    text: "Open the menu bar list and click a snippet to paste it into the active app."
                )
                feature(
                    icon: "pin",
                    title: "Always at hand",
                    text: "The list is only a click away in the menu bar."
                )
            }
            .frame(maxWidth: 320, alignment: .leading)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private func feature(icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))

                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Empty detail state for "groups exist, but none is selected".
struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "folder")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)

            Text("Select a group")
                .font(.system(size: 12.5, weight: .medium))

            Text("Choose a group in the sidebar to see its snippets.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
