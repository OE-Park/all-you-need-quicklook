// AllYouNeedQuickLook/Views/SettingsView.swift
import SwiftUI
import Shared

struct SettingsView: View {
    @State private var config: AppConfig
    @State private var newExtension = ""
    @State private var saveError: String?
    private let loader = ConfigLoader()

    init() {
        let loaded = ConfigLoader().load()
        _config = State(initialValue: loaded)
    }

    var body: some View {
        Form {
            Section("Global Settings") {
                TextField("Font Family", text: $config.global.fontFamily)
                Stepper("Font Size: \(config.global.fontSize)", value: $config.global.fontSize, in: 8...36)
                HStack {
                    Text("Line Height:")
                    Slider(value: $config.global.lineHeight, in: 1.0...3.0, step: 0.1)
                    Text(String(format: "%.1f", config.global.lineHeight))
                        .monospacedDigit()
                }
                Toggle("Show Line Numbers", isOn: $config.global.showLineNumbers)
                Toggle("Allow External Images", isOn: $config.global.allowExternalImages)
                Text("External images can contact internet or local network servers and reveal when a file is previewed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Image Timeout: \(config.global.imageTimeoutSeconds)s",
                        value: $config.global.imageTimeoutSeconds, in: 1...30)
            }

            Section("File Type Settings") {
                ForEach(sortedFileTypes, id: \.key) { entry in
                    DisclosureGroup(entry.key) {
                        fileTypeEditor(for: entry.key)
                    }
                }

                HStack {
                    TextField("Add extension (e.g. yaml)", text: $newExtension)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let ext = newExtension.trimmingCharacters(in: .whitespaces).lowercased()
                        guard !ext.isEmpty else { return }
                        if config.fileTypes == nil { config.fileTypes = [:] }
                        // Assigning unconditionally would overwrite an existing
                        // entry — typing "log" would wipe its level patterns.
                        guard config.fileTypes?[ext] == nil else {
                            newExtension = ""
                            return
                        }
                        config.fileTypes?[ext] = FileTypeConfig()
                        newExtension = ""
                    }
                    .disabled(newExtension.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                HStack {
                    Button("Reset to Default") {
                        // The default is the bundled default-config.json, not
                        // `AppConfig()` — that one has no fileTypes at all, and
                        // saving it would drop the log level patterns for good.
                        config = ConfigLoader.bundledDefault()
                        save()
                    }
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert(
            "Could not save settings",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private var sortedFileTypes: [(key: String, value: FileTypeConfig)] {
        (config.fileTypes ?? [:]).sorted { $0.key < $1.key }
    }

    @ViewBuilder
    private func fileTypeEditor(for ext: String) -> some View {
        let binding = Binding<FileTypeConfig>(
            get: { config.fileTypes?[ext] ?? FileTypeConfig() },
            set: { config.fileTypes?[ext] = $0 }
        )

        Toggle("Syntax Highlight", isOn: Binding(
            get: { binding.wrappedValue.syntaxHighlight ?? false },
            set: { binding.wrappedValue.syntaxHighlight = $0 }
        ))

        if binding.wrappedValue.syntaxHighlight == true {
            TextField("Language (e.g. xml, yaml)", text: Binding(
                get: { binding.wrappedValue.syntaxLanguage ?? "" },
                set: { binding.wrappedValue.syntaxLanguage = $0.isEmpty ? nil : $0 }
            ))
        }

        Toggle("Show Line Numbers", isOn: Binding(
            get: { binding.wrappedValue.showLineNumbers ?? config.global.showLineNumbers },
            set: { binding.wrappedValue.showLineNumbers = $0 }
        ))

        HStack {
            Spacer()
            Button("Remove", role: .destructive) {
                config.fileTypes?.removeValue(forKey: ext)
            }
            .foregroundStyle(.red)
        }
    }

    /// The only persistence path in the app, Reset included. Swallowing the
    /// error here would show a Save that appears to have worked while the
    /// extension goes on reading the old file — or, if the App Group container
    /// is unavailable, a file in a temporary directory that it never reads.
    private func save() {
        do {
            try loader.save(config)
        } catch {
            saveError = error.localizedDescription
        }
    }
}
