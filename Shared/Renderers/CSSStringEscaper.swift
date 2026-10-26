// Shared/Renderers/CSSStringEscaper.swift
import Foundation

/// Escapes untrusted text for a double-quoted CSS string literal.
///
/// The configured font family reaches the document as
/// `font-family: "<value>"` inside an inline `<style>`. Unescaped, a value
/// carrying `"` closes the string and the rest is parsed as CSS -- and a
/// `</style` inside it closes the element itself, because `<style>` is
/// RAWTEXT and the parser does not care that it sits inside a string.
///
/// `<` is emitted as the CSS escape `\3C ` rather than removed, so the
/// character still renders in a font name while never reaching the HTML
/// tokenizer as markup. Newlines are escaped for the same reason a raw one is
/// invalid in a CSS string: it would terminate the declaration.
public enum CSSStringEscaper {

    public static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "<", with: "\\3C ")
            .replacingOccurrences(of: "\n", with: "\\A ")
            .replacingOccurrences(of: "\r", with: "\\D ")
    }
}
