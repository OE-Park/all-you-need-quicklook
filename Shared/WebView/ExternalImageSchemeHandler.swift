import Foundation
import WebKit

struct LoadedImage: Sendable {
    let data: Data
    let mimeType: String
}

final class ExternalImageLoader: @unchecked Sendable {
    private static let maximumBytes = 25 * 1_024 * 1_024
    private let delegate: StreamingImageSessionDelegate
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
        let delegate = StreamingImageSessionDelegate(maximumBytes: Self.maximumBytes)
        self.delegate = delegate
        self.session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func load(_ url: URL) async throws -> LoadedImage {
        guard Self.isAllowed(url) else { throw URLError(.unsupportedURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try await delegate.load(request, using: session)
    }

    fileprivate static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

private final class StreamingImageSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private final class Transfer: @unchecked Sendable {
        let continuation: CheckedContinuation<LoadedImage, any Error>
        var data = Data()
        var mimeType: String?
        var validationError: (any Error)?

        init(continuation: CheckedContinuation<LoadedImage, any Error>) {
            self.continuation = continuation
        }
    }

    private let maximumBytes: Int
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
    }

    func load(_ request: URLRequest, using session: URLSession) async throws -> LoadedImage {
        let dataTask = session.dataTask(with: request)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    transfers[dataTask.taskIdentifier] = Transfer(continuation: continuation)
                }
                dataTask.resume()
            }
        } onCancel: {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let disposition: URLSession.ResponseDisposition = lock.withLock {
            guard let transfer = transfers[dataTask.taskIdentifier],
                  let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let responseURL = httpResponse.url,
                  ExternalImageLoader.isAllowed(responseURL),
                  let mimeType = httpResponse.mimeType,
                  mimeType.lowercased().hasPrefix("image/"),
                  httpResponse.expectedContentLength <= Int64(maximumBytes) else {
                transfers[dataTask.taskIdentifier]?.validationError = URLError(.cannotDecodeContentData)
                return .cancel
            }

            transfer.mimeType = mimeType
            if httpResponse.expectedContentLength > 0 {
                transfer.data.reserveCapacity(Int(httpResponse.expectedContentLength))
            }
            return .allow
        }
        completionHandler(disposition)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let exceededLimit = lock.withLock {
            guard let transfer = transfers[dataTask.taskIdentifier] else { return false }
            guard data.count <= maximumBytes - transfer.data.count else {
                transfer.validationError = URLError(.cannotDecodeContentData)
                return true
            }
            transfer.data.append(data)
            return false
        }
        if exceededLimit {
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        guard let transfer = lock.withLock({ transfers.removeValue(forKey: task.taskIdentifier) }) else {
            return
        }

        if let validationError = transfer.validationError {
            transfer.continuation.resume(throwing: validationError)
        } else if let error {
            transfer.continuation.resume(throwing: error)
        } else if let mimeType = transfer.mimeType {
            transfer.continuation.resume(returning: LoadedImage(data: transfer.data, mimeType: mimeType))
        } else {
            transfer.continuation.resume(throwing: URLError(.cannotDecodeContentData))
        }
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
