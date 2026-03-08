import Foundation

public struct HookInput: Codable {
    public let sessionId: String?
    public let toolName: String
    public let toolInput: [String: AnyCodable]
    public let cwd: String?
    public let permissionMode: String?
    public let hookEventName: String?

    public let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case cwd
        case permissionMode = "permission_mode"
        case hookEventName = "hook_event_name"
        case transcriptPath = "transcript_path"
    }

    public var command: String? {
        toolInput["command"]?.stringValue
    }

    public var filePath: String? {
        toolInput["file_path"]?.stringValue
    }

    /// Claude's description of what the command does (Bash tool_input.description)
    public var toolDescription: String? {
        toolInput["description"]?.stringValue
    }

    public var toolInputAsString: String {
        if let data = try? JSONEncoder().encode(toolInput),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }
}

/// Type-erased Codable wrapper for JSON values
public struct AnyCodable: Codable {
    public let value: Any

    public var stringValue: String? {
        value as? String
    }

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            value = str
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let str as String: try container.encode(str)
        case let int as Int: try container.encode(int)
        case let double as Double: try container.encode(double)
        case let bool as Bool: try container.encode(bool)
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let arr as [Any]:
            try container.encode(arr.map { AnyCodable($0) })
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }
}
