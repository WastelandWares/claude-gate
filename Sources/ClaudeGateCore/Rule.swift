import Foundation

public enum RuleAction: String, Codable {
    case passthrough
    case gate
    case deny
}

public enum RiskLevel: String, Codable {
    case critical
    case high
    case medium
    case low
}

public struct Rule {
    public let name: String
    public let tool: String
    public let pattern: String?
    public let pathPattern: String?
    public let action: RuleAction
    public let reason: String
    public let risk: RiskLevel
    public let gracePeriod: TimeInterval  // seconds, 0 = always re-auth
}
