// AllYouNeedQuickLook/Views/PreviewView.swift
import SwiftUI
import Shared

struct PreviewView: View {

    struct SampleFile: Identifiable, Hashable {
        let id: String
        let name: String
        let ext: String
    }

    private let samples: [SampleFile] = [
        SampleFile(id: "md", name: "sample.md", ext: "md"),
        SampleFile(id: "txt", name: "sample.txt", ext: "txt"),
        SampleFile(id: "log", name: "sample.log", ext: "log"),
        SampleFile(id: "ipynb", name: "sample.ipynb", ext: "ipynb"),
    ]

    @State private var selectedSample: SampleFile?

    /// The rendered document, recomputed when the selection changes.
    ///
    /// Rendering inside `body` re-read the sample from disk, re-read
    /// `config.json` from the App Group and rebuilt the whole ~475 KB template
    /// on *every* body evaluation, handing the web view a fresh string each
    /// time. Doing it here means one render per selection.
    @State private var renderedHTML: String?

    private static let resourcesURL = Bundle(for: ConfigLoader.self).resourceURL

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSample) {
                ForEach(samples) { sample in
                    Label(sample.name, systemImage: iconForExtension(sample.ext))
                        .tag(sample)
                }
            }
            .navigationTitle("Samples")
        } detail: {
            if let html = renderedHTML {
                PreviewWebViewRepresentable(html: html, resourcesURL: Self.resourcesURL)
            } else {
                ContentUnavailableView(
                    "Select a Sample File",
                    systemImage: "doc",
                    description: Text("Choose a file from the sidebar to preview.")
                )
            }
        }
        .onChange(of: selectedSample) { _, sample in
            renderedHTML = sample.map(Self.render)
        }
    }

    private static func render(_ sample: SampleFile) -> String {
        let content = loadSampleContent(sample.name)
        let config = ConfigLoader().load()
        let renderer: Renderer = switch sample.ext {
        case "md", "markdown": MarkdownRenderer()
        case "ipynb": NotebookRenderer()
        default: PlainTextRenderer()
        }
        return renderer.render(content: content, config: config, fileExtension: sample.ext)
    }

    private static func loadSampleContent(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: nil)
                ?? Bundle.main.url(
                    forResource: (name as NSString).deletingPathExtension,
                    withExtension: (name as NSString).pathExtension
                ),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return "Error: Could not load \(name)"
        }
        return content
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext {
        case "md": return "doc.richtext"
        case "txt": return "doc.text"
        case "log": return "terminal"
        case "ipynb": return "tablecells"
        default: return "doc"
        }
    }
}
