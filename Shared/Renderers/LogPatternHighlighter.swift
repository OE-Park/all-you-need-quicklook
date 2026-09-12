import Foundation
import JavaScriptCore

/// One bounded compile/match budget per rendered plain-text document.
/// No document data is interpolated into JavaScript source.
final class LogPatternHighlighter {
    private let context: JSContext?
    private var matcher: JSValue?
    private var budget: JSValue?
    private var programs: [(String, JSValue)] = []
    private var exhausted = false
    private(set) var skipped = false

    private static let scripts: [String] = ["bounded-pattern-compiler", "bounded-pattern-matcher"].compactMap {
        guard let url = Bundle(for: ConfigLoader.self).url(forResource: $0, withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    init(patterns: [String: String]) {
        context = JSContext()
        guard let context, Self.scripts.count == 2 else { skipped = true; return }
        for script in Self.scripts { context.evaluateScript(script) }
        guard context.exception == nil,
              let compiler = context.objectForKeyedSubscript("BoundedPatternCompiler"),
              let compileBudget = compiler.invokeMethod("createBudget", withArguments: []) else { skipped = true; return }
        matcher = context.objectForKeyedSubscript("BoundedPatternMatcher")
        budget = matcher?.invokeMethod("createBudget", withArguments: [])
        for level in ["error", "warn", "info", "debug"] {
            guard let pattern = patterns[level] else { continue }
            let result = compiler.invokeMethod("compile", withArguments: [pattern, compileBudget])
            if result?.forProperty("status")?.toString() == "compiled",
               let program = result?.forProperty("program") {
                programs.append((level, program))
            } else { skipped = true }
        }
    }

    func renderLine(_ line: String) -> String {
        guard !exhausted, !programs.isEmpty, let matcher, let budget else { return HTMLEscaper.escape(line) }
        var groups: [[String: Any]] = []
        for (level, program) in programs {
            let result = matcher.invokeMethod("findMatches", withArguments: [program, line, budget])
            guard result?.forProperty("status")?.toString() == "matched",
                  let matches = result?.forProperty("matches")?.toArray() else {
                skipped = true
                // A long line is skipped independently; exhausted document budgets stay stopped.
                exhausted = result?.forProperty("status")?.toString() != "skipped"
                return HTMLEscaper.escape(line)
            }
            groups.append(["kind": "level", "level": level, "matches": matches])
        }
        let result = matcher.invokeMethod("resolveRun", withArguments: [groups, budget])
        guard result?.forProperty("status")?.toString() == "resolved",
              let segments = result?.forProperty("segments")?.toArray() as? [[String: Any]] else {
            skipped = true
            exhausted = true
            return HTMLEscaper.escape(line)
        }
        let source = line as NSString
        var pieces: [String] = []
        var end = 0
        for segment in segments {
            guard let start = segment["start"] as? Int, let stop = segment["end"] as? Int,
                  let level = segment["level"] as? String,
                  ["error", "warn", "info", "debug"].contains(level),
                  start >= end, stop >= start, stop <= source.length else {
                skipped = true
                return HTMLEscaper.escape(line)
            }
            pieces.append(HTMLEscaper.escape(source.substring(with: NSRange(location: end, length: start - end))))
            let text = HTMLEscaper.escape(source.substring(with: NSRange(location: start, length: stop - start)))
            pieces.append("<span class=\"log-\(level)\">\(text)</span>")
            end = stop
        }
        pieces.append(HTMLEscaper.escape(source.substring(from: end)))
        return pieces.joined()
    }
}
