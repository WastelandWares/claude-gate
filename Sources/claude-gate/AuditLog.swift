import Foundation

struct AuditEntry: Codable {
    let timestamp: String
    let sessionId: String?
    let toolName: String
    let command: String?
    let filePath: String?
    let ruleName: String?
    let ruleAction: String
    let decision: String
    let reason: String
    let risk: String?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case sessionId = "session_id"
        case toolName = "tool_name"
        case command
        case filePath = "file_path"
        case ruleName = "rule_name"
        case ruleAction = "rule_action"
        case decision
        case reason
        case risk
        case cwd
    }
}

class AuditLog {
    static let shared = AuditLog()

    private let logPath: String

    private init() {
        let configDir = NSString("~/.config/claude-gate").expandingTildeInPath
        self.logPath = (configDir as NSString).appendingPathComponent("audit.jsonl")
    }

    func log(input: HookInput, rule: Rule?, action: RuleAction, decision: String, reason: String) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let entry = AuditEntry(
            timestamp: formatter.string(from: Date()),
            sessionId: input.sessionId,
            toolName: input.toolName,
            command: input.command,
            filePath: input.filePath,
            ruleName: rule?.name,
            ruleAction: action.rawValue,
            decision: decision,
            reason: reason,
            risk: rule?.risk.rawValue,
            cwd: input.cwd
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(entry),
              var line = String(data: data, encoding: .utf8) else {
            return
        }
        line += "\n"

        // Append to file, creating if needed
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                handle.closeFile()
            }
        } else {
            // Ensure directory exists
            let dir = (logPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}
