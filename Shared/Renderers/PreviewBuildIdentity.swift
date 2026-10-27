import Foundation

/// Test copies identify themselves in Finder; shipping previews are unchanged.
public enum PreviewBuildIdentity {
    public static func annotate(_ html: String, identifier: String?) -> String {
        guard let tail = identifier?.components(separatedBy: ".test.").last,
              identifier?.contains(".test.") == true,
              let suffix = tail.split(separator: ".").first.map(String.init),
              suffix.range(of: "^[a-f0-9]{8}$", options: .regularExpression) != nil,
              let body = html.range(of: "<body[^>]*>", options: .regularExpression) else { return html }
        var result = html
        result.insert(contentsOf: "<div class=\"settings-notice\" role=\"status\">Test build \(suffix)</div>", at: body.upperBound)
        return result
    }
}
