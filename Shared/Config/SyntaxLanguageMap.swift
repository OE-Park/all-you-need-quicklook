// Shared/Config/SyntaxLanguageMap.swift
import Foundation

/// File extension to highlight.js language id.
///
/// Swift cannot ask the web view what the bundled highlight.js knows, so the
/// answer is kept here instead. Every id below is registered by the bundled
/// `common` build (37 grammars); `SyntaxLanguageMapTests` re-checks that
/// against the shipped `highlight.min.js` so a library bump cannot quietly
/// invalidate an entry.
///
/// A `nil` result means "no language for this extension" and leaves
/// `syntaxHighlight` off by default, so the file renders as plain text rather
/// than as whatever `highlightAuto` guesses.
///
/// `log` and `txt` are deliberately absent. `log` drives the bounded
/// log-level pattern path in `PlainTextRenderer`, which only runs while
/// `syntaxLanguage` is nil; giving it a language would divert the renderer
/// into the hljs branch and silently drop every configured level pattern.
public enum SyntaxLanguageMap {

    private static let table: [String: String] = [
        // Data and configuration — the formats that hang off `public.text`
        // rather than `public.plain-text`.
        "json": "json", "jsonl": "json", "ndjson": "json", "jsonc": "json", "json5": "json",
        "yaml": "yaml", "yml": "yaml",
        // highlight.js has no TOML grammar; `toml` is its own alias for `ini`.
        "toml": "ini", "ini": "ini", "cfg": "ini", "conf": "ini", "properties": "ini",
        "xml": "xml", "xsd": "xml", "xsl": "xml", "xslt": "xml", "plist": "xml",
        "svg": "xml", "html": "xml", "htm": "xml", "xhtml": "xml", "vue": "xml",

        // Stylesheets
        "css": "css", "scss": "scss", "sass": "scss", "less": "less",

        // Sources
        "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript", "mts": "typescript", "cts": "typescript",
        "py": "python", "pyw": "python", "pyi": "python",
        "rb": "ruby", "rake": "ruby", "gemfile": "ruby", "podspec": "ruby",
        "php": "php", "java": "java", "kt": "kotlin", "kts": "kotlin",
        "swift": "swift", "go": "go", "rs": "rust",
        "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp", "hxx": "cpp",
        "cs": "csharp", "vb": "vbnet",
        "m": "objectivec", "mm": "objectivec",
        "lua": "lua", "pl": "perl", "pm": "perl", "r": "r",

        // Shells and build files
        "sh": "bash", "bash": "bash", "zsh": "bash", "ksh": "bash",
        "makefile": "makefile", "mk": "makefile",

        // Everything else the common build covers
        "sql": "sql", "graphql": "graphql", "gql": "graphql",
        "diff": "diff", "patch": "diff",
        "md": "markdown", "markdown": "markdown",
        "wat": "wasm", "wasm": "wasm",
    ]

    /// The highlight.js language id for `fileExtension`, or nil when the
    /// bundled build has no grammar for it.
    public static func language(forExtension fileExtension: String) -> String? {
        table[fileExtension.lowercased()]
    }

    /// Every distinct language id the table can return, sorted. Test-facing: it is what
    /// `SyntaxLanguageMapTests` checks against the shipped bundle.
    public static var allLanguages: [String] { Array(Set(table.values)).sorted() }
}
