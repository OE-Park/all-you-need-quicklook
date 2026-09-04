import Foundation
import XCTest
@testable import Shared

final class ExternalImageLoaderTests: XCTestCase {

    func testAppliesConfiguredTimeoutToImageRequest() async {
        let loader = ExternalImageLoader(
            timeout: 0.1,
            protocolClasses: [HangingURLProtocol.self]
        )

        do {
            _ = try await loader.load(URL(string: "https://example.test/image.png")!)
            XCTFail("Expected the image request to time out")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Expected URLError.timedOut, got \(error)")
        }
    }

    func testStopsOversizedResponseBeforeEntireBodyIsRead() async {
        OversizedImageURLProtocol.reset()
        let loader = ExternalImageLoader(
            timeout: 5,
            protocolClasses: [OversizedImageURLProtocol.self]
        )

        do {
            _ = try await loader.load(URL(string: "https://example.test/oversized.png")!)
            XCTFail("Expected the oversized image to be rejected")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cannotDecodeContentData)
        } catch {
            XCTFail("Expected URLError.cannotDecodeContentData, got \(error)")
        }

        XCTAssertLessThan(
            OversizedImageURLProtocol.bytesSent,
            OversizedImageURLProtocol.totalBytes,
            "The loader consumed the entire oversized response before rejecting it"
        )
    }
}

private final class HangingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {}

    override func stopLoading() {}
}

private final class OversizedImageURLProtocol: URLProtocol, @unchecked Sendable {
    static let chunkSize = 1_024 * 1_024
    static let chunkCount = 30
    static let totalBytes = chunkSize * chunkCount

    private static let metricsLock = NSLock()
    nonisolated(unsafe) private static var recordedBytesSent = 0

    private let stateLock = NSLock()
    private var stopped = false

    static var bytesSent: Int {
        metricsLock.withLock { recordedBytesSent }
    }

    static func reset() {
        metricsLock.withLock { recordedBytesSent = 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "image/png"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let chunk = Data(repeating: 0x41, count: Self.chunkSize)
        for _ in 0..<Self.chunkCount {
            guard !stateLock.withLock({ stopped }) else { return }
            client?.urlProtocol(self, didLoad: chunk)
            Self.metricsLock.withLock { Self.recordedBytesSent += chunk.count }
            Thread.sleep(forTimeInterval: 0.005)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
    }
}
