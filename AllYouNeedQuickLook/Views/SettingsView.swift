// AllYouNeedQuickLook/Views/SettingsView.swift
import SwiftUI
import Shared

struct SettingsView: View {
    @State private var config: AppConfig
    @State private var newExtension = ""
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
                        config.fileTypes?[ext] = FileTypeConfig()
                        newExtension = ""
                    }
                    .disabled(newExtension.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section {
                HStack {
                    Button("Reset to Default") {
                        config = AppConfig()
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

    private func save() {
        try? loader.save(config)
    }
}
