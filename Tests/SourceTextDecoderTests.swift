import XCTest
@testable import Shared

final class SourceTextDecoderTests: XCTestCase {
    func testPowerShellUnicodeBOMsPreserveTextWithoutNULs() throws {
        let text = "Write-Host \"안녕 QuickLook\"\r\n"
        for (bom, encoding) in [([UInt8(0xff),0xfe], String.Encoding.utf16LittleEndian),
                                ([0xfe,0xff], .utf16BigEndian),
                                ([0xff,0xfe,0,0], .utf32LittleEndian),
                                ([0,0,0xfe,0xff], .utf32BigEndian)] {
            let data = Data(bom) + (try XCTUnwrap(text.data(using: encoding)))
            XCTAssertEqual(try SourceTextDecoder.decode(data), text)
        }
    }

    func testUTF8BOMAndLegacyLatin1() throws {
        XCTAssertEqual(try SourceTextDecoder.decode(Data([0xef,0xbb,0xbf]) + Data("echo hello".utf8)), "echo hello")
        XCTAssertEqual(try SourceTextDecoder.decode(Data([0x63,0x61,0x66,0xe9])), "café")
        XCTAssertEqual(try SourceTextDecoder.decode(Data()), "")
    }

    func testMalformedUnicodeDoesNotFallThroughToLatin1() {
        XCTAssertThrowsError(try SourceTextDecoder.decode(Data([0xff,0xfe,0x41])))
    }
}
