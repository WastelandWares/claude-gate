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
    private let queue = DispatchQueue(label: "com.claude-gate.audit")

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
            FileHandle.standardError.write(Data("claude-gate: WARNING — failed to encode audit log entry\n".utf8))
            return
        }
        line += "\n"

        queue.sync {
            writeEntry(line)
        }
    }

    private func writeEntry(_ line: String) {
        if FileManager.default.fileExists(atPath: logPath) {
            guard let handle = FileHandle(forWritingAtPath: logPath) else {
                FileHandle.standardError.write(Data("claude-gate: WARNING — failed to open audit log for writing\n".utf8))
                return
            }
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
        } else {
            let dir = (logPath as NSString).deletingLastPathComponent
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                try line.write(toFile: logPath, atomically: false, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("claude-gate: WARNING — failed to create audit log: \(error.localizedDescription)\n".utf8))
            }
        }
    }
}
