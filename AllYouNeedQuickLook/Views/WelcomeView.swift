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
                Text("Preview source code, scripts, Markdown, logs, and notebooks in Finder.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Label("Markdown (.md) — rendered with syntax highlighting and math", systemImage: "doc.richtext")
                Label("Source & scripts — PowerShell, Bash, Python, Swift, C/C++, and more", systemImage: "chevron.left.forwardslash.chevron.right")
                Label("Logs (.log) — configurable formatting", systemImage: "doc.text")
                Label("Jupyter Notebooks (.ipynb) — full cell rendering", systemImage: "terminal")

                // `.txt` resolves to public.plain-text, the same type macOS's own
                // text preview declares -- and the built-in one wins. The Preview
                // tab in this app still renders .txt with the configured settings.
                Text("macOS may use its built-in preview for .txt when several providers qualify. Use the Preview tab to see your formatting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.body)
            .padding(.horizontal, 40)

            Divider().padding(.horizontal, 60)

            VStack(spacing: 12) {
                Text("Manage Quick Look in macOS")
                    .font(.headline)

                Text("Turn previews on or off in System Settings. Formatting preferences in this app do not activate extensions.")
                    .font(.caption).foregroundStyle(.secondary)

                Text("System Settings → General → Login Items & Extensions → Quick Look")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Open System Settings") {
                    _ = ExtensionSettings.open()
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
    }

}
