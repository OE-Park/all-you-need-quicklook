// AllYouNeedQuickLook/Views/WelcomeView.swift
import SwiftUI
import AppKit

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "eye.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("All You Need QuickLook")
                    .font(.largeTitle.bold())
                Text("Preview Markdown, text files, and Jupyter Notebooks in Finder.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Label("Markdown (.md) — rendered with syntax highlighting and math", systemImage: "doc.richtext")
                Label("Text & Logs (.txt, .log, ...) — configurable formatting", systemImage: "doc.text")
                Label("Jupyter Notebooks (.ipynb) — full cell rendering", systemImage: "terminal")
            }
            .font(.body)
            .padding(.horizontal, 40)

            Divider().padding(.horizontal, 60)

            VStack(spacing: 12) {
                Text("Enable the QuickLook Extension")
                    .font(.headline)

                Text("System Settings > Privacy & Security > Extensions > Quick Look")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Open System Settings") {
                    openExtensionSettings()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

    private func openExtensionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }
}
