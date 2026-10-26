// AllYouNeedQuickLook/Views/SettingsView.swift
import SwiftUI
import Shared
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var config: AppConfig
    @State private var newExtension = ""
    @State private var saveError: String?
    @State private var statusMessage: String?
    @State private var showingImport = false
    private let support = FileTypeSupport.bundled()
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
                Toggle("Allow External Images", isOn: .constant(false))
                    .disabled(true)
                Text("Remote images are unavailable in this version. Embedded and local images still work.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Image Timeout: \(config.global.imageTimeoutSeconds)s",
                        value: $config.global.imageTimeoutSeconds, in: 1...30)
                    .disabled(true)
            }

            Section("File Type Settings") {
                Text("Adding an extension saves its formatting immediately. Finder support also requires a file type declared by this app and the Quick Look extension enabled in System Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Manage Quick Look in System Settings") {
                    if !ExtensionSettings.open() { saveError = ExtensionSettings.instructions }
                }
                Text(ExtensionSettings.instructions).font(.caption).foregroundStyle(.secondary)
                if let statusMessage { Text(statusMessage).font(.callout).accessibilityIdentifier("fileTypeStatus") }

                ForEach(sortedFileTypes, id: \.key) { entry in
                    DisclosureGroup(entry.key) {
                        Text(supportDescription(for: entry.key))
                            .font(.caption).foregroundStyle(.secondary)
                        fileTypeEditor(for: entry.key)
                    }
                }

                HStack {
                    TextField("Add extension (e.g. yaml)", text: $newExtension)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        do {
                            config = try loader.saveAddedFileType(newExtension, draft: config)
                            let ext = FileTypeSupport.normalizedExtension(newExtension)!
                            statusMessage = ".\(ext) saved. Other draft edits still require Save. " + supportDescription(for: ext)
                            newExtension = ""
                        } catch { saveError = error.localizedDescription }
                    }
                    .disabled(FileTypeSupport.normalizedExtension(newExtension) == nil)
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
                    Button("Import Settings JSON…") { showingImport = true }
                    Spacer()
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try loader.importConfiguration(from: url)
                config = loader.load()
                statusMessage = "Settings imported. Reopen the Finder preview to apply them."
            } catch {
                if (error as NSError).code != NSUserCancelledError { saveError = error.localizedDescription }
            }
        }
        .alert(
            "Could not save settings",
            isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func supportDescription(for ext: String) -> String {
        switch support.status(for: ext) {
        case .eligible:
            return "Declared Finder type. Enable Quick Look in System Settings; macOS chooses the provider."
        case .unsupported:
            return "Formatting preference saved. This file type is not declared for Finder; System Settings cannot add it."
        case .unknown:
            return "Formatting preference saved. macOS has no registered type for this extension; Finder support is unavailable."
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
            get: { config.resolvedConfig(for: ext).syntaxHighlight },
            set: { binding.wrappedValue.syntaxHighlight = $0 }
        ))

        if config.resolvedConfig(for: ext).syntaxHighlight {
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
    /// extension goes on reading the old file.
    private func save() {
        do {
            try loader.save(config)
            statusMessage = "Settings saved. Reopen the Finder preview to apply them."
        } catch {
            saveError = error.localizedDescription
        }
    }
}
