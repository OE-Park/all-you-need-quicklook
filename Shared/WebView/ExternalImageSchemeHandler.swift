import Foundation
import WebKit

struct LoadedImage: Sendable {
    let data: Data
    let mimeType: String
}

final class ExternalImageLoader: @unchecked Sendable {
    private static let maximumBytes = 25 * 1_024 * 1_024
    private let session: URLSession
    private let timeout: TimeInterval

    init(timeout: TimeInterval, protocolClasses: [AnyClass]? = nil) {
        self.timeout = max(timeout, 0.1)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = self.timeout
        configuration.timeoutIntervalForResource = self.timeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        self.session = URLSession(configuration: configuration)
    }

    func load(_ url: URL) async throws -> LoadedImage {
        guard Self.isAllowed(url) else { throw URLError(.unsupportedURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let responseURL = httpResponse.url,
              Self.isAllowed(responseURL),
              let mimeType = httpResponse.mimeType,
              mimeType.lowercased().hasPrefix("image/"),
              data.count <= Self.maximumBytes else {
            throw URLError(.cannotDecodeContentData)
        }
        return LoadedImage(data: data, mimeType: mimeType)
    }

    private static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

private final class URLSchemeTaskBox: @unchecked Sendable {
    let task: any WKURLSchemeTask

    init(_ task: any WKURLSchemeTask) {
        self.task = task
    }
}

final class ExternalImageSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    nonisolated static let scheme = "quicklook-image"

    private let loader: ExternalImageLoader
    private let lock = NSLock()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(timeout: TimeInterval) {
        self.loader = ExternalImageLoader(timeout: timeout)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        let box = URLSchemeTaskBox(urlSchemeTask)
        let loader = self.loader
        let operation = Task { [weak self] in
            defer { self?.removeTask(identifier) }
            do {
                guard let originalURL = Self.originalURL(from: box.task.request.url) else {
                    throw URLError(.badURL)
                }
                let image = try await loader.load(originalURL)
                guard !Task.isCancelled else { return }
                let response = URLResponse(
                    url: box.task.request.url ?? originalURL,
                    mimeType: image.mimeType,
                    expectedContentLength: image.data.count,
                    textEncodingName: nil
                )
                box.task.didReceive(response)
                box.task.didReceive(image.data)
                box.task.didFinish()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                box.task.didFailWithError(error)
            }
        }
        lock.withLock {
            tasks[identifier] = operation
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let identifier = ObjectIdentifier(urlSchemeTask as AnyObject)
        lock.withLock {
            tasks.removeValue(forKey: identifier)
        }?.cancel()
    }

    private static func originalURL(from requestURL: URL?) -> URL? {
        guard let requestURL,
              requestURL.host == "fetch",
              let components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false),
              let value = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private func removeTask(_ identifier: ObjectIdentifier) {
        _ = lock.withLock {
            tasks.removeValue(forKey: identifier)
        }
    }
}
