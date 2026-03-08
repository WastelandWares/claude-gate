import XCTest
@testable import ClaudeGateCore

final class RuleEngineTests: XCTestCase {

    private func fixturePath(_ name: String) -> String {
        Bundle.module.path(forResource: name, ofType: "toml", inDirectory: "Fixtures")!
    }

    private func makeInput(tool: String, command: String? = nil, filePath: String? = nil) -> HookInput {
        var toolInput: [String: AnyCodable] = [:]
        if let command = command {
            toolInput["command"] = AnyCodable(command)
        }
        if let filePath = filePath {
            toolInput["file_path"] = AnyCodable(filePath)
        }
        return try! JSONDecoder().decode(HookInput.self, from: JSONSerialization.data(withJSONObject: [
            "tool_name": tool,
            "tool_input": toolInput.mapValues { $0.value }
        ]))
    }

    // MARK: - Rule Matching

    func testPassthroughForSafeCommand() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "ls -la")
        let (rule, action) = engine.evaluate(input)
        XCTAssertNil(rule)
        XCTAssertEqual(action, .passthrough)
    }

    func testDenyForRmRf() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "rm -rf /")
        let (rule, action) = engine.evaluate(input)
        XCTAssertNotNil(rule)
        XCTAssertEqual(action, .deny)
        XCTAssertEqual(rule?.name, "Block: rm -rf /")
    }

    func testDenyForRmRfHome() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "rm -rf ~/Documents")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .deny)
    }

    func testDenyForRmWithMultipleFlags() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "rm -rf /etc/hosts")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .deny)
    }

    func testGateForForcePush() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "git push --force origin main")
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: force push")
    }

    func testGateForNpmInstall() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "npm install lodash")
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: npm install")
    }

    func testGateForYarnAdd() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "yarn add react")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
    }

    func testPassthroughForNormalGitPush() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "git push origin main")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .passthrough)
    }

    func testPassthroughForRmSafeFile() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Bash", command: "rm temp.txt")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - Path Pattern Matching

    func testGateForEnvFileWrite() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Write", filePath: "/project/.env")
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: env files")
    }

    func testGateForSshConfigEdit() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Edit", filePath: "/Users/me/.ssh/config")
        let (rule, action) = engine.evaluate(input)
        XCTAssertEqual(action, .gate)
        XCTAssertEqual(rule?.name, "Gate: ssh config")
    }

    func testPassthroughForNormalFileWrite() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "Write", filePath: "/project/src/main.swift")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - First Match Wins

    func testFirstMatchWins() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        // rm -rf / matches the deny rule before any gate rule
        let input = makeInput(tool: "Bash", command: "rm -rf /")
        let (_, action) = engine.evaluate(input)
        XCTAssertEqual(action, .deny)
    }

    // MARK: - Unmatched Tool

    func testUnmatchedToolUsesDefault() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        let input = makeInput(tool: "UnknownTool", command: "anything")
        let (rule, action) = engine.evaluate(input)
        XCTAssertNil(rule)
        XCTAssertEqual(action, .passthrough)
    }

    // MARK: - Config Parsing

    func testDefaultTimeout() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertEqual(engine.timeout, 60)
        XCTAssertEqual(engine.timeoutAction, .deny)
    }

    func testCustomTimeout() throws {
        let engine = try RuleEngine(configPath: fixturePath("custom-timeout"))
        XCTAssertEqual(engine.timeout, 120)
        XCTAssertEqual(engine.timeoutAction, .passthrough)
    }

    func testTimeoutMinimumClamping() throws {
        let engine = try RuleEngine(configPath: fixturePath("low-timeout"))
        XCTAssertEqual(engine.timeout, 5, "Timeout should be clamped to minimum 5 seconds")
    }

    func testPassthroughTimeoutMinimumClamping() throws {
        let engine = try RuleEngine(configPath: fixturePath("passthrough-low-timeout"))
        XCTAssertEqual(engine.timeout, 30, "Timeout should be clamped to 30s when timeout_action is passthrough")
    }

    func testDefaultActionGate() throws {
        let engine = try RuleEngine(configPath: fixturePath("custom-timeout"))
        XCTAssertEqual(engine.defaultAction, .gate)
    }

    func testVoiceDisabledByDefault() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertFalse(engine.voiceEnabled)
    }

    func testAuditDisabledByDefault() throws {
        let engine = try RuleEngine(configPath: fixturePath("test-rules"))
        XCTAssertFalse(engine.auditEnabled)
    }

    // MARK: - Malformed Config

    func testMalformedRuleSkipped() throws {
        let engine = try RuleEngine(configPath: fixturePath("malformed"))
        XCTAssertEqual(engine.rules.count, 0, "Malformed rules should be skipped")
    }

    func testMissingConfigThrows() {
        XCTAssertThrowsError(try RuleEngine(configPath: "/nonexistent/path.toml"))
    }

    // MARK: - HookOutput

    func testHookOutputAllow() {
        let output = HookOutput.allow(reason: "test")
        let json = output.toJSON()
        XCTAssertTrue(json.contains("\"permissionDecision\":\"allow\""))
        XCTAssertTrue(json.contains("\"permissionDecisionReason\":\"test\""))
    }

    func testHookOutputDeny() {
        let output = HookOutput.deny(reason: "blocked")
        let json = output.toJSON()
        XCTAssertTrue(json.contains("\"permissionDecision\":\"deny\""))
        XCTAssertTrue(json.contains("\"permissionDecisionReason\":\"blocked\""))
    }

    // MARK: - HookInput Parsing

    func testHookInputParsing() throws {
        let json = """
        {"tool_name":"Bash","tool_input":{"command":"ls -la","description":"List files"},"cwd":"/tmp"}
        """
        let input = try JSONDecoder().decode(HookInput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(input.toolName, "Bash")
        XCTAssertEqual(input.command, "ls -la")
        XCTAssertEqual(input.toolDescription, "List files")
        XCTAssertEqual(input.cwd, "/tmp")
    }

    func testHookInputMinimal() throws {
        let json = """
        {"tool_name":"Bash","tool_input":{}}
        """
        let input = try JSONDecoder().decode(HookInput.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(input.toolName, "Bash")
        XCTAssertNil(input.command)
        XCTAssertNil(input.filePath)
        XCTAssertNil(input.cwd)
    }
}
