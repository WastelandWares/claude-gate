import Foundation

struct HookInput: Codable {
    let sessionId: String?
    let toolName: String
    let toolInput: [String: AnyCodable]
    let cwd: String?
    let permissionMode: String?
    let hookEventName: String?

    let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case cwd
        case permissionMode = "permission_mode"
        case hookEventName = "hook_event_name"
        case transcriptPath = "transcript_path"
    }

    var command: String? {
        toolInput["command"]?.stringValue
    }

    var filePath: String? {
        toolInput["file_path"]?.stringValue
    }

    /// Claude's description of what the command does (Bash tool_input.description)
    var toolDescription: String? {
        toolInput["description"]?.stringValue
    }

    var toolInputAsString: String {
        if let data = try? JSONEncoder().encode(toolInput),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }
}

/// Type-erased Codable wrapper for JSON values
struct AnyCodable: Codable {
    let value: Any

    var stringValue: String? {
        value as? String
    }

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
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

    func encode(to encoder: Encoder) throws {
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
