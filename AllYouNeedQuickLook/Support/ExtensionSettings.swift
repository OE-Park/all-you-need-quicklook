import AppKit

@MainActor
enum ExtensionSettings {
    static let instructions = "System Settings → General → Login Items & Extensions → Quick Look. Enable All You Need QuickLook. macOS chooses the preview provider for supported file types; enabling an extension does not register new types."

    @discardableResult
    static func open() -> Bool {
        // Pane URLs are best effort and can vary between macOS releases.
        for address in [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.ExtensionsPreferences"
        ] {
            if let url = URL(string: address), NSWorkspace.shared.open(url) { return true }
        }
        return false
    }
}
