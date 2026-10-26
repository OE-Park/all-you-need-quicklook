import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit

enum LocalImageError: Error, Equatable {
    case noDocumentDirectory
    case notRelative
    case notFound
    case notRegularFile
    case notAnImage
    case tooLarge
}

/// Serves the images a previewed document refers to by relative path.
///
/// The page script rewrites `<img src="pic.png">` to
/// `quicklook-local://image/?ref=<src as written>`; this handler resolves the
/// reference against the directory of the file being previewed. The page
/// cannot do that itself: it is loaded with the *bundle's* resource directory
/// as `baseURL`, and its opaque origin could not read a sibling file anyway.
///
/// Only images leave this handler. A reference must be relative (no scheme, no
/// leading `/`); `..` is allowed, because documents legitimately point at
/// `../assets/x.png`. Symlinks are resolved *before* the checks, so a link to
/// a directory or a non-image is refused and a link to an image elsewhere is
/// served. Quick Look has already granted read access to the previewed file's
/// neighbourhood; the guard against serving other data is the image test, not
/// the location.
final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    nonisolated static let scheme = "quicklook-local"
    nonisolated static let maxBytes = 25 * 1_024 * 1_024

    private let lock = NSLock()
    private var documentDirectory: URL?

    func setDocumentDirectory(_ url: URL?) {
        lock.withLock {
            documentDirectory = url
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              requestURL.host == "image",
              let ref = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "ref" })?.value else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        do {
            guard let directory = lock.withLock({ documentDirectory }) else {
                throw LocalImageError.noDocumentDirectory
            }
            let fileURL = try Self.resolve(ref: ref, in: directory)
            let image = try Self.validatedImage(at: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: image.mimeType,
                expectedContentLength: image.data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(image.data)
            urlSchemeTask.didFinish()
        } catch LocalImageError.notRelative, LocalImageError.noDocumentDirectory {
            urlSchemeTask.didFailWithError(URLError(.badURL))
        } catch {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

    // MARK: - Resolution

    /// Turns the `src` as written in the document into a file URL beside it.
    ///
    /// `ref` arrives decoded once already by `URLComponents` (the page
    /// `encodeURIComponent`s it into the query), which leaves the literal
    /// `src`. It is percent-decoded exactly once more here, as a browser would
    /// decode a relative URL's path, so `a%20b.png` and `a b.png` both name
    /// `a b.png`. A `?query` or `#fragment` belongs to the URL, not the file
    /// name, and is cut off *before* decoding so an encoded `%3F` stays a
    /// literal `?`.
    static func resolve(ref: String, in directory: URL) throws -> URL {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = trimmed.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? trimmed.endIndex
        let rawPath = String(trimmed[..<end])
        let path = rawPath.removingPercentEncoding ?? rawPath

        for candidate in [rawPath, path] {
            guard !candidate.isEmpty,
                  !candidate.hasPrefix("/"),
                  candidate.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) == nil else {
                throw LocalImageError.notRelative
            }
        }

        let url = directory.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { throw LocalImageError.notFound }
        return url
    }

    // MARK: - Validation

    /// Reads `url` only if it is a regular file, of an image type, small
    /// enough, and its bytes really are an image.
    ///
    /// The size is taken from the file system before any byte is read, so an
    /// oversized file costs nothing. The extension is a cheap first filter;
    /// the bytes are the authority, which is what stops `notes.txt` renamed to
    /// `x.png`, or an `.svg` that is really HTML, from being served as an image.
    static func validatedImage(at url: URL) throws -> (data: Data, mimeType: String) {
        let resolved = url.resolvingSymlinksInPath()
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            throw LocalImageError.notFound
        }
        guard values.isRegularFile == true else { throw LocalImageError.notRegularFile }
        guard let type = UTType(filenameExtension: resolved.pathExtension), type.conforms(to: .image) else {
            throw LocalImageError.notAnImage
        }
        guard (values.fileSize ?? 0) <= maxBytes else { throw LocalImageError.tooLarge }
        guard let data = try? Data(contentsOf: resolved) else { throw LocalImageError.notFound }

        if type.conforms(to: .svg) {
            guard hasSVGRoot(data) else { throw LocalImageError.notAnImage }
            return (data, "image/svg+xml")
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let identifier = CGImageSourceGetType(source) as String?,
              let mimeType = UTType(identifier)?.preferredMIMEType else {
            throw LocalImageError.notAnImage
        }
        return (data, mimeType)
    }

    private static func hasSVGRoot(_ data: Data) -> Bool {
        final class RootFinder: NSObject, XMLParserDelegate {
            var rootName: String?
            func parser(
                _ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]
            ) {
                rootName = elementName
                parser.abortParsing()
            }
        }
        let finder = RootFinder()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = finder
        parser.parse()
        guard let name = finder.rootName else { return false }
        return name == "svg" || name.hasSuffix(":svg")
    }
}
