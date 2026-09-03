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
}

private final class HangingURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {}

    override func stopLoading() {}
}
