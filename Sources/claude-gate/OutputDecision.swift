import Foundation

struct OutputDecision: Codable {
    let decision: String
    let reason: String

    static func approve(reason: String = "No matching rule") -> OutputDecision {
        OutputDecision(decision: "approve", reason: reason)
    }

    static func deny(reason: String) -> OutputDecision {
        OutputDecision(decision: "deny", reason: reason)
    }

    func toJSON() -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"decision\": \"deny\", \"reason\": \"Failed to encode decision\"}"
        }
        return str
    }
}
