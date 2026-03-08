import Foundation

/// Appends new rules to the user's rules.toml config file.
class RuleWriter {
    /// Generate and append a passthrough or deny rule based on the current gate context.
    /// The rule is inserted at the top of the [[rules]] section so it takes priority (first-match-wins).
    static func addRule(
        action: RuleAction,
        toolName: String,
        command: String?,
        filePath: String?,
        cwd: String?,
        originalRuleName: String
    ) -> Bool {
        let configPath = NSString("~/.config/claude-gate/rules.toml").expandingTildeInPath

        guard FileManager.default.fileExists(atPath: configPath) else {
            FileHandle.standardError.write(Data("claude-gate: Cannot add rule — config not found at \(configPath)\n".utf8))
            return false
        }

        guard var contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            FileHandle.standardError.write(Data("claude-gate: Cannot read config at \(configPath)\n".utf8))
            return false
        }

        // Build the pattern from the command or file path
        let pattern: String
        let patternField: String
        if let cmd = command {
            // Escape regex special characters and create an exact-match pattern
            pattern = NSRegularExpression.escapedPattern(for: cmd)
            patternField = "pattern"
        } else if let path = filePath {
            pattern = NSRegularExpression.escapedPattern(for: path)
            patternField = "path_pattern"
        } else {
            FileHandle.standardError.write(Data("claude-gate: Cannot create rule — no command or file path\n".utf8))
            return false
        }

        let actionStr = action == .passthrough ? "passthrough" : "deny"
        let ruleNamePrefix = action == .passthrough ? "Always allow" : "Always deny"
        let shortPattern = pattern.count > 60 ? String(pattern.prefix(57)) + "..." : pattern

        // Build the TOML rule block
        var ruleBlock = "\n[[rules]]\n"
        ruleBlock += "name = \"\(ruleNamePrefix): \(shortPattern)\"\n"
        ruleBlock += "tool = \"\(toolName)\"\n"
        ruleBlock += "\(patternField) = '^\(pattern)$'\n"
        ruleBlock += "action = \"\(actionStr)\"\n"
        ruleBlock += "reason = \"User-created rule (was: \(originalRuleName))\"\n"
        ruleBlock += "risk = \"low\"\n"

        // Insert after the [defaults] section but before existing [[rules]]
        // Find the first [[rules]] and insert before it
        if let range = contents.range(of: "[[rules]]") {
            contents.insert(contentsOf: ruleBlock + "\n", at: range.lowerBound)
        } else {
            // No existing rules — append at end
            contents += ruleBlock
        }

        do {
            try contents.write(toFile: configPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            FileHandle.standardError.write(Data("claude-gate: Failed to write rule: \(error.localizedDescription)\n".utf8))
            return false
        }
    }
}
