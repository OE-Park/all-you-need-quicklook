// Shared/Config/SyntaxLanguageMap.swift
import Foundation

/// File extension to highlight.js language id.
///
/// Swift cannot ask the web view what the bundled highlight.js knows, so the
/// answer is kept here instead. Every id below is registered by the bundled
/// common build plus version-matched supplemental grammars; `SyntaxLanguageMapTests` re-checks that
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
        "wat": "wasm",

        // Additional bundled grammars; unsupported grammars use explicit plain text.
        "abap": "plaintext",
        "ada": "plaintext",
        "adb": "plaintext",
        "ads": "plaintext",
        "ahk": "plaintext",
        "apache": "apache",
        "asm": "armasm",
        "asmdef": "plaintext",
        "asmref": "plaintext",
        "astro": "xml",
        "atom": "xml",
        "au3": "plaintext",
        "automount": "ini",
        "awk": "plaintext",
        "axaml": "xml",
        "bash_profile": "bash",
        "bashrc": "bash",
        "bat": "dos",
        "c++": "cpp",
        "cbl": "plaintext",
        "cl": "lisp",
        "clj": "clojure",
        "cljc": "clojure",
        "cljs": "clojure",
        "cls": "latex",
        "cmake": "cmake",
        "cmd": "dos",
        "cnf": "ini",
        "cob": "plaintext",
        "command": "bash",
        "containerfile": "dockerfile",
        "cr": "plaintext",
        "csproj": "xml",
        "csx": "csharp",
        "cu": "plaintext",
        "cuh": "plaintext",
        "d": "plaintext",
        "dart": "dart",
        "ddl": "sql",
        "desktop": "ini",
        "dml": "sql",
        "dockerfile": "dockerfile",
        "dtx": "latex",
        "e": "plaintext",
        "editorconfig": "ini",
        "edn": "clojure",
        "eex": "plaintext",
        "elm": "plaintext",
        "env": "bash",
        "erl": "erlang",
        "es6": "javascript",
        "ex": "elixir",
        "exs": "elixir",
        "f": "fortran",
        "f03": "fortran",
        "f08": "fortran",
        "f90": "fortran",
        "f95": "fortran",
        "fish": "plaintext",
        "for": "fortran",
        "frag": "plaintext",
        "fs": "fsharp",
        "fsi": "fsharp",
        "fsproj": "xml",
        "fsscript": "fsharp",
        "fsx": "fsharp",
        "gd": "plaintext",
        "gemspec": "ruby",
        "geom": "plaintext",
        "glsl": "plaintext",
        "gradle": "gradle",
        "groovy": "groovy",
        "gsh": "groovy",
        "gvy": "groovy",
        "gy": "groovy",
        "h++": "cpp",
        "hcl": "plaintext",
        "heex": "plaintext",
        "hppin": "plaintext",
        "hrl": "erlang",
        "hs": "haskell",
        "htaccess": "apache",
        "inc": "plaintext",
        "ino": "cpp",
        "ipp": "cpp",
        "jl": "julia",
        "jsm": "javascript",
        "leex": "plaintext",
        "lhs": "haskell",
        "lisp": "lisp",
        "lsp": "lisp",
        "ltx": "latex",
        "matlab": "matlab",
        "metal": "plaintext",
        "ml": "ocaml",
        "mli": "ocaml",
        "mount": "ini",
        "move": "plaintext",
        "nginx": "nginx",
        "nim": "nim",
        "nims": "nim",
        "nix": "nix",
        "pas": "plaintext",
        "path": "ini",
        "pde": "plaintext",
        "php3": "php",
        "php4": "php",
        "php5": "php",
        "phps": "php",
        "phtml": "php",
        "pom": "xml",
        "pp": "plaintext",
        "prefs": "ini",
        "prg": "plaintext",
        "pro": "prolog",
        "profile": "bash",
        "prolog": "prolog",
        "props": "xml",
        "proto": "protobuf",
        "ps1": "powershell",
        "ps1xml": "xml",
        "psd1": "powershell",
        "psm1": "powershell",
        "psrc": "powershell",
        "pssc": "powershell",
        "purs": "plaintext",
        "pxd": "python",
        "pxi": "python",
        "pyx": "python",
        "rdf": "xml",
        "reg": "ini",
        "resx": "xml",
        "rkt": "plaintext",
        "rss": "xml",
        "ru": "ruby",
        "s": "armasm",
        "sc": "scala",
        "scala": "scala",
        "scm": "scheme",
        "sed": "plaintext",
        "service": "ini",
        "sld": "scheme",
        "socket": "ini",
        "sol": "plaintext",
        "ss": "scheme",
        "sty": "latex",
        "sv": "verilog",
        "svelte": "xml",
        "svh": "verilog",
        "target": "ini",
        "targets": "xml",
        "tcl": "plaintext",
        "tex": "latex",
        "tf": "plaintext",
        "tfvars": "plaintext",
        "timer": "ini",
        "tk": "plaintext",
        "tpp": "cpp",
        "v": "verilog",
        "vala": "plaintext",
        "vapi": "plaintext",
        "vbe": "plaintext",
        "vbproj": "xml",
        "vbs": "plaintext",
        "vert": "plaintext",
        "vh": "verilog",
        "vhd": "vhdl",
        "vhdl": "vhdl",
        "wgsl": "plaintext",
        "wsdl": "xml",
        "xaml": "xml",
        "xlf": "xml",
        "xliff": "xml",
        "zig": "plaintext",
        "zon": "plaintext",
        "zprofile": "bash",
        "zshrc": "bash",
    ]

    /// The highlight.js language id for `fileExtension`, or nil when the
    /// bundled build has no grammar for it.
    public static func language(forExtension fileExtension: String) -> String? {
        table[fileExtension.lowercased()]
    }

    public static var allExtensions: [String] { table.keys.sorted() }

    /// Every distinct language id the table can return, sorted. Test-facing: it is what
    /// `SyntaxLanguageMapTests` checks against the shipped bundle.
    public static var allLanguages: [String] { Array(Set(table.values)).sorted() }
}
