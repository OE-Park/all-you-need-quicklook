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

    /// The rendered document, recomputed on selection or successful settings save.
    ///
    /// Rendering inside `body` re-read the sample from disk, re-read
    /// `config.json` from the App Group and rebuilt the whole ~475 KB template
    /// on *every* body evaluation, handing the web view a fresh string each
    /// time. Doing it here means one render per selection.
    @State private var rendered: RenderedSample?

    /// A composed document and the nonce it was composed with. The two are
    /// inseparable: `PreviewWebView` arms `script-src` with this nonce, so a
    /// document paired with any other one renders blank.
    struct RenderedSample: Equatable {
        let html: String
        let nonce: String
        let imageTimeoutSeconds: TimeInterval
        let allowExternalImages: Bool
    }

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
            if let rendered {
                PreviewWebViewRepresentable(
                    html: rendered.html, nonce: rendered.nonce, resourcesURL: Self.resourcesURL,
                    imageTimeoutSeconds: rendered.imageTimeoutSeconds,
                    allowExternalImages: rendered.allowExternalImages
                )
                .id(rendered.imageTimeoutSeconds)
                .id(rendered.allowExternalImages)
            } else {
                ContentUnavailableView(
                    "Select a Sample File",
                    systemImage: "doc",
                    description: Text("Choose a file from the sidebar to preview.")
                )
            }
        }
        .onChange(of: selectedSample) { _, sample in
            rendered = sample.map(Self.render)
        }
        .onReceive(NotificationCenter.default.publisher(for: ConfigLoader.didSave).receive(on: RunLoop.main)) { _ in
            rendered = selectedSample.map(Self.render)
        }
    }

    private static func render(_ sample: SampleFile) -> RenderedSample {
        let content = loadSampleContent(sample.name)
        let config = ConfigLoader().load()
        let renderer: Renderer = switch sample.ext {
        case "md", "markdown": MarkdownRenderer()
        case "ipynb": NotebookRenderer()
        default: PlainTextRenderer()
        }
        let nonce = PreviewWebView.makeNonce()
        return RenderedSample(
            html: renderer.render(
                content: content, config: config, fileExtension: sample.ext, nonce: nonce
            ),
            nonce: nonce,
            imageTimeoutSeconds: TimeInterval(config.global.imageTimeoutSeconds),
            allowExternalImages: config.global.allowExternalImages
        )
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
