import Foundation

/// Windows PowerShell commonly writes UTF-16LE with a BOM. Inspect BOMs before
/// the legacy Latin-1 fallback, which would otherwise accept every UTF-16 byte.
public enum SourceTextDecoder {
    public static func read(from url: URL) throws -> String {
        try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> String {
        let boms: [([UInt8], String.Encoding)] = [
            ([0xff, 0xfe, 0, 0], .utf32LittleEndian),
            ([0, 0, 0xfe, 0xff], .utf32BigEndian),
            ([0xef, 0xbb, 0xbf], .utf8),
            ([0xff, 0xfe], .utf16LittleEndian),
            ([0xfe, 0xff], .utf16BigEndian),
        ]
        for (bom, encoding) in boms where data.starts(with: bom) {
            let payload = data.dropFirst(bom.count)
            let unitSize = encoding == .utf32LittleEndian || encoding == .utf32BigEndian ? 4
                : (encoding == .utf16LittleEndian || encoding == .utf16BigEndian ? 2 : 1)
            guard payload.count.isMultiple(of: unitSize),
                  let text = String(data: payload, encoding: encoding) else {
                throw CocoaError(.fileReadInapplicableStringEncoding)
            }
            return text
        }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }
}
