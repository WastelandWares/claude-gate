import Foundation
import TOMLKit

public class RuleEngine {
    public let defaultAction: RuleAction
    public let rules: [Rule]
    public let timeoutAction: RuleAction
    public let voiceEnabled: Bool
    public let auditEnabled: Bool
    public private(set) var timeout: TimeInterval

    public init(configPath: String) throws {
        let tomlString = try String(contentsOfFile: configPath, encoding: .utf8)
        let table = try TOMLTable(string: tomlString)

        // Parse [defaults] section
        if let defaults = table["defaults"]?.table,
           let actionStr = defaults["action"]?.string,
           let action = RuleAction(rawValue: actionStr) {
            self.defaultAction = action
        } else {
            self.defaultAction = .gate
        }

        // Parse timeout (default 60 seconds, minimum 5 seconds)
        if let defaults = table["defaults"]?.table,
           let t = defaults["timeout"]?.int {
            self.timeout = TimeInterval(max(t, 5))
            if t < 5 {
                FileHandle.standardError.write(
                    Data("claude-gate: Warning: timeout clamped to minimum 5 seconds (was \(t))\n".utf8)
                )
            }
        } else {
            self.timeout = 60
        }

        // Parse timeout_action (default deny)
        if let defaults = table["defaults"]?.table,
           let actionStr = defaults["timeout_action"]?.string,
           let action = RuleAction(rawValue: actionStr) {
            self.timeoutAction = action
        } else {
            self.timeoutAction = .deny
        }

        // Parse voice setting (default false)
        if let defaults = table["defaults"]?.table,
           let v = defaults["voice"]?.bool {
            self.voiceEnabled = v
        } else {
            self.voiceEnabled = false
        }

        // Parse audit setting (default false — opt-in)
        if let defaults = table["defaults"]?.table,
           let a = defaults["audit"]?.bool {
            self.auditEnabled = a
        } else {
            self.auditEnabled = false
        }

        // Safety: passthrough on timeout can bypass auth — enforce minimum 30s
        if self.timeoutAction == .passthrough && self.timeout < 30 {
            FileHandle.standardError.write(
                Data("claude-gate: Warning: timeout clamped to 30s because timeout_action is passthrough (auto-approve)\n".utf8)
            )
            self.timeout = 30
        }

        // Parse [[rules]] section
        var parsedRules: [Rule] = []
        if let rulesArray = table["rules"]?.array {
            for i in 0..<rulesArray.count {
                guard let ruleTable = rulesArray[i].table else { continue }

                guard let name = ruleTable["name"]?.string,
                      let tool = ruleTable["tool"]?.string,
                      let actionStr = ruleTable["action"]?.string,
                      let action = RuleAction(rawValue: actionStr),
                      let reason = ruleTable["reason"]?.string,
                      let riskStr = ruleTable["risk"]?.string,
                      let risk = RiskLevel(rawValue: riskStr) else {
                    let ruleName = ruleTable["name"]?.string ?? "rule[\(i)]"
                    FileHandle.standardError.write(
                        Data("claude-gate: Warning: Skipping malformed rule '\(ruleName)' — missing or invalid required field\n".utf8)
                    )
                    continue
                }

                let pattern = ruleTable["pattern"]?.string
                let pathPattern = ruleTable["path_pattern"]?.string
                let gracePeriod = TimeInterval(ruleTable["grace_period"]?.int ?? 0)

                let rule = Rule(
                    name: name,
                    tool: tool,
                    pattern: pattern,
                    pathPattern: pathPattern,
                    action: action,
                    reason: reason,
                    risk: risk,
                    gracePeriod: gracePeriod
                )
                parsedRules.append(rule)
            }
        }
        self.rules = parsedRules
    }

    public func evaluate(_ input: HookInput) -> (Rule?, RuleAction) {
        let matchingRules = rules.filter { toolMatches(pattern: $0.tool, toolName: input.toolName) }

        for rule in matchingRules {
            if matches(rule: rule, input: input) {
                return (rule, rule.action)
            }
        }

        return (nil, defaultAction)
    }

    // MARK: - Private

    private func matches(rule: Rule, input: HookInput) -> Bool {
        // Use the actual tool name for the switch, not the rule's (possibly wildcard) pattern
        switch input.toolName {
        case "Bash":
            guard let pattern = rule.pattern else { return true }
            guard let command = input.command else { return false }
            return regexMatch(pattern: pattern, text: command)

        case "Write", "Edit":
            if let pathPattern = rule.pathPattern, let filePath = input.filePath {
                if !regexMatch(pattern: pathPattern, text: filePath) {
                    return false
                }
            } else if rule.pathPattern != nil {
                return false
            }

            if let pattern = rule.pattern, let filePath = input.filePath {
                if !regexMatch(pattern: pattern, text: filePath) {
                    return false
                }
            } else if rule.pattern != nil {
                return false
            }

            return true

        default:
            guard let pattern = rule.pattern else { return true }
            // For MCP/Agent tools, match pattern against both tool name and input JSON.
            // This allows patterns like "write_note|delete_note" to match the MCP action
            // in the tool name (e.g., mcp__obsidian__write_note).
            let text = input.toolName + " " + input.toolInputAsString
            return regexMatch(pattern: pattern, text: text)
        }
    }

    /// Match a rule's tool field against the actual tool name.
    /// Supports exact match and glob-style wildcards:
    ///   "Bash"              — exact match
    ///   "mcp__*"            — matches any MCP tool
    ///   "mcp__obsidian__*"  — matches any Obsidian MCP tool
    ///   "Agent"             — exact match
    func toolMatches(pattern: String, toolName: String) -> Bool {
        if !pattern.contains("*") {
            return pattern == toolName
        }
        // Convert glob to regex safely:
        // 1. Escape ALL regex metacharacters using NSRegularExpression
        // 2. Then convert escaped glob wildcards (\*) back to regex (.*)
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        return regexMatch(pattern: regexPattern, text: toolName)
    }

    private func regexMatch(pattern: String, text: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..., in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } catch {
            FileHandle.standardError.write(
                Data("Warning: Invalid regex pattern '\(pattern)': \(error.localizedDescription)\n".utf8)
            )
            return false
        }
    }
}
