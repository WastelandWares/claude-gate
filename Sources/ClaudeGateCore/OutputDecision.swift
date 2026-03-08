import Foundation

public struct HookOutput: Codable {
    public let hookSpecificOutput: HookSpecificOutput

    public struct HookSpecificOutput: Codable {
        public let hookEventName: String
        public let permissionDecision: String
        public let permissionDecisionReason: String?
    }

    public static func allow(reason: String? = nil) -> HookOutput {
        HookOutput(hookSpecificOutput: HookSpecificOutput(
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            permissionDecisionReason: reason
        ))
    }

    public static func deny(reason: String) -> HookOutput {
        HookOutput(hookSpecificOutput: HookSpecificOutput(
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: reason
        ))
    }

    public func toJSON() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"Failed to encode decision\"}}"
        }
        return str
    }
}
