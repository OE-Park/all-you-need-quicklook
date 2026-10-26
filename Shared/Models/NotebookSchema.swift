// Shared/Models/NotebookSchema.swift
import Foundation

public struct Notebook: Codable, Sendable {
    public let nbformat: Int
    public let nbformatMinor: Int
    public let cells: [Cell]

    enum CodingKeys: String, CodingKey {
        case nbformat
        case nbformatMinor = "nbformat_minor"
        case cells
        case metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nbformat = try container.decode(Int.self, forKey: .nbformat)
        nbformatMinor = try container.decode(Int.self, forKey: .nbformatMinor)
        cells = try container.decode([Cell].self, forKey: .cells)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(nbformat, forKey: .nbformat)
        try container.encode(nbformatMinor, forKey: .nbformatMinor)
        try container.encode(cells, forKey: .cells)
        try container.encode([String: String](), forKey: .metadata)
    }
}

public enum CellType: String, Codable, Sendable {
    case markdown
    case code
    case raw
}

public struct Cell: Codable, Sendable {
    public let cellType: CellType
    public let source: [String]
    public let outputs: [CellOutput]?
    public let executionCount: Int?

    public var joinedSource: String { source.joined() }

    enum CodingKeys: String, CodingKey {
        case cellType = "cell_type"
        case source, outputs, metadata
        case executionCount = "execution_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cellType = try container.decode(CellType.self, forKey: .cellType)
        source = try decodeMultilineString(from: container, forKey: .source)
        outputs = try container.decodeIfPresent([CellOutput].self, forKey: .outputs)
        executionCount = try container.decodeIfPresent(Int?.self, forKey: .executionCount) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cellType, forKey: .cellType)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(outputs, forKey: .outputs)
        try container.encode(executionCount, forKey: .executionCount)
        try container.encode([String: String](), forKey: .metadata)
    }
}

public enum CellOutput: Codable, Sendable {
    case stream(StreamOutput)
    case displayData(DisplayDataOutput)
    case executeResult(ExecuteResultOutput)
    case error(ErrorOutput)

    enum CodingKeys: String, CodingKey {
        case outputType = "output_type"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .outputType)
        switch type {
        case "stream":
            self = .stream(try StreamOutput(from: decoder))
        case "display_data":
            self = .displayData(try DisplayDataOutput(from: decoder))
        case "execute_result":
            self = .executeResult(try ExecuteResultOutput(from: decoder))
        case "error":
            self = .error(try ErrorOutput(from: decoder))
        default:
            self = .stream(StreamOutput(name: "stdout", text: ["[unsupported output type: \(type)]"]))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .stream(let o): try o.encode(to: encoder)
        case .displayData(let o): try o.encode(to: encoder)
        case .executeResult(let o): try o.encode(to: encoder)
        case .error(let o): try o.encode(to: encoder)
        }
    }
}

public struct StreamOutput: Codable, Sendable {
    public let name: String
    public let text: [String]

    enum CodingKeys: String, CodingKey {
        case name, text
    }

    public init(name: String, text: [String]) {
        self.name = name
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        text = try decodeMultilineString(from: container, forKey: .text)
    }
}

public struct DisplayDataOutput: Codable, Sendable {
    public let data: [String: MimeData]

    enum CodingKeys: String, CodingKey {
        case data, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode([String: MimeData].self, forKey: .data)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
        try container.encode([String: String](), forKey: .metadata)
    }
}

public struct ExecuteResultOutput: Codable, Sendable {
    public let executionCount: Int?
    public let data: [String: MimeData]

    enum CodingKeys: String, CodingKey {
        case executionCount = "execution_count"
        case data, metadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        executionCount = try container.decodeIfPresent(Int.self, forKey: .executionCount)
        data = try container.decode([String: MimeData].self, forKey: .data)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(executionCount, forKey: .executionCount)
        try container.encode(data, forKey: .data)
        try container.encode([String: String](), forKey: .metadata)
    }
}

public struct ErrorOutput: Codable, Sendable {
    public let ename: String
    public let evalue: String
    public let traceback: [String]
}

public enum MimeData: Codable, Sendable {
    case string(String)
    case array([String])
    /// A JSON object payload (the Plotly figure is the one that matters),
    /// re-encoded as compact JSON text. Decoding it into text here keeps the
    /// type `Sendable` without holding an `Any` tree.
    case json(String)

    public var text: String {
        switch self {
        case .string(let s): return s
        case .array(let a): return a.joined()
        case .json: return ""
        }
    }

    /// The compact JSON text of an object payload; nil for the text cases.
    public var jsonText: String? {
        if case .json(let text) = self { return text }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .array(arr)
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let value = try? container.decode(JSONValue.self), case .object = value,
                  let data = try? JSONEncoder().encode(value),
                  let text = String(data: data, encoding: .utf8) {
            self = .json(text)
        } else {
            self = .string("")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .json(let text):
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
            try container.encode(value)
        }
    }
}

/// Any JSON value, so an object-valued MIME bundle entry can be carried
/// through `Codable` and re-encoded without loss. Internal to this file.
private enum JSONValue: Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let v): try container.encode(v)
        case .number(let v): try container.encode(v)
        case .string(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        }
    }
}

private func decodeMultilineString<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) throws -> [String] {
    do {
        return try container.decode([String].self, forKey: key)
    } catch DecodingError.typeMismatch {
        return [try container.decode(String.self, forKey: key)]
    }
}
