// Shared/Renderers/ScriptEscaping.swift
import Foundation

/// Escaping for Swift-side content interpolated into an **inline** `<script>`
/// element.
///
/// Two different escapes are needed and both are needed at once:
///
/// - The JavaScript literal the value lands in must not be terminable, or the
///   value becomes code.
/// - The `<script>` *element* must not be terminable either. Escaping the
///   literal does nothing about that: the HTML tokenizer runs before the JS
///   parser, so a literal `</script` in the payload ends the element and
///   everything after it is parsed as markup — which
///   `script-src 'unsafe-inline'` then happily executes.
///
/// Both renderers used to carry their own copy of this and only one of them
/// neutralised `</script`, which is exactly the divergence this type exists to
/// prevent. Every Swift value interpolated into a `<script>` body goes through
/// one of these.
enum ScriptEscaping {

    /// Escapes `string` for a JavaScript template literal (`` `…` ``) inside an
    /// inline `<script>` element.
    static func forTemplateLiteral(_ string: String) -> String {
        neutralizingScriptEnd(
            string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
        )
    }

    /// Escapes `string` for a single-quoted JavaScript string literal inside an
    /// inline `<script>` element.
    ///
    /// Line terminators are escaped as well: unlike a template literal, a
    /// single-quoted literal cannot span lines.
    static func forSingleQuotedLiteral(_ string: String) -> String {
        neutralizingScriptEnd(
            string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\r\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\n")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        )
    }

    /// `</script` optionally followed by whitespace, `>` or `/` — the sequences
    /// the HTML tokenizer accepts as the end of a script element.
    ///
    /// Must run *after* backslashes have been escaped, or the backslash this
    /// introduces would itself be doubled. `\/` is a legal identity escape in
    /// every literal form this type emits into, so the replacement is the same
    /// string to JavaScript and no longer a tag to the tokenizer.
    private static let scriptEnd = try! NSRegularExpression(
        pattern: "</script(?=[\\s>/]|$)",
        options: .caseInsensitive
    )

    private static func neutralizingScriptEnd(_ string: String) -> String {
        scriptEnd.stringByReplacingMatches(
            in: string,
            range: NSRange(string.startIndex..., in: string),
            withTemplate: "<\\\\/script"
        )
    }
}
