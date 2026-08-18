// Shared/Renderers/ANSIConverter.swift
import Foundation

public enum ANSIConverter {

    private static let ansiColors: [Int: String] = [
        30: "#1d1d1f", 31: "#d32f2f", 32: "#388e3c", 33: "#f57c00",
        34: "#1976d2", 35: "#7b1fa2", 36: "#0097a7", 37: "#f5f5f7",
        90: "#7b7b7b", 91: "#ff6b6b", 92: "#66bb6a", 93: "#ffb74d",
        94: "#64b5f6", 95: "#ce93d8", 96: "#4dd0e1", 97: "#ffffff",
    ]

    private static let ansiPattern = try! NSRegularExpression(
        pattern: "\u{1B}\\[([0-9;]*)m",
        options: []
    )

    public static func toHTML(_ input: String) -> String {
        let escaped = escapeHTML(input)
        let nsString = escaped as NSString
        let matches = ansiPattern.matches(
            in: escaped,
            range: NSRange(location: 0, length: nsString.length)
        )

        guard !matches.isEmpty else { return escaped }

        var result = ""
        var lastIndex = escaped.startIndex
        var spanOpen = false

        for match in matches {
            guard let fullRange = Range(match.range, in: escaped),
                  let codeRange = Range(match.range(at: 1), in: escaped) else { continue }

            result += escaped[lastIndex..<fullRange.lowerBound]
            let codes = escaped[codeRange].split(separator: ";").compactMap { Int($0) }

            if spanOpen {
                result += "</span>"
                spanOpen = false
            }

            let styles = buildStyles(from: codes)
            if !styles.isEmpty {
                result += "<span style=\"\(styles)\">"
                spanOpen = true
            }

            lastIndex = fullRange.upperBound
        }

        result += escaped[lastIndex...]
        if spanOpen { result += "</span>" }

        return result
    }

    private static func buildStyles(from codes: [Int]) -> String {
        var parts: [String] = []
        for code in codes {
            if code == 0 {
                parts.removeAll()
                continue
            }
            if code == 1 { parts.append("font-weight:bold") }
            if code == 3 { parts.append("font-style:italic") }
            if code == 4 { parts.append("text-decoration:underline") }
            if let color = ansiColors[code] {
                parts.append("color:\(color)")
            }
        }
        return parts.joined(separator: ";")
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
