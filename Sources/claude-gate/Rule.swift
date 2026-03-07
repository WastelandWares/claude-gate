import Foundation

enum RuleAction: String, Codable {
    case passthrough
    case gate
    case deny
}

enum RiskLevel: String, Codable {
    case critical
    case high
    case medium
    case low
}

struct Rule {
    let name: String
    let tool: String
    let pattern: String?
    let pathPattern: String?
    let action: RuleAction
    let reason: String
    let risk: RiskLevel
}
