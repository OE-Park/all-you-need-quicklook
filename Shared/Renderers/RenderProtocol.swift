// Shared/Renderers/RenderProtocol.swift
import Foundation

public protocol Renderer {
    /// Composes a complete preview document for `content`.
    ///
    /// `nonce` is this document's CSP nonce: every `<script>` the renderer
    /// emits must carry it, or the policy `PreviewWebView` installs for the
    /// same load will refuse to run it. Get it from
    /// `PreviewWebView.makeNonce()`, once per document.
    func render(content: String, config: AppConfig, fileExtension: String, nonce: String) -> String
}
