import Foundation
import AppKit

// Read JSON from stdin
let inputData: Data
if let data = Optional(FileHandle.standardInput.availableData), !data.isEmpty {
    inputData = data
} else {
    // No input — passthrough
    print(OutputDecision.approve(reason: "No input received").toJSON())
    exit(0)
}

// Parse hook input
let input: HookInput
do {
    input = try JSONDecoder().decode(HookInput.self, from: inputData)
} catch {
    FileHandle.standardError.write(Data("claude-gate: Failed to parse input: \(error.localizedDescription)\n".utf8))
    print(OutputDecision.approve(reason: "Failed to parse input, allowing by default").toJSON())
    exit(0)
}

// Load rules
let configPath = NSString("~/.config/claude-gate/rules.toml").expandingTildeInPath
let engine: RuleEngine
do {
    engine = try RuleEngine(configPath: configPath)
} catch {
    FileHandle.standardError.write(Data("claude-gate: Failed to load rules from \(configPath): \(error.localizedDescription)\n".utf8))
    print(OutputDecision.approve(reason: "Failed to load rules, allowing by default").toJSON())
    exit(0)
}

// Evaluate
let (matchedRule, action) = engine.evaluate(input)

switch action {
case .passthrough:
    print(OutputDecision.approve(reason: matchedRule?.name ?? "No matching rule").toJSON())
    exit(0)

case .deny:
    let reason = matchedRule?.reason ?? "Denied by rule"
    FileHandle.standardError.write(Data("claude-gate: DENIED — \(reason)\n".utf8))
    print(OutputDecision.deny(reason: reason).toJSON())
    exit(2)

case .gate:
    guard let rule = matchedRule else {
        print(OutputDecision.approve(reason: "No rule for gate action").toJSON())
        exit(0)
    }

    // Determine the command/content text to display
    let displayText: String
    if let cmd = input.command {
        displayText = cmd
    } else if let path = input.filePath {
        displayText = "\(input.toolName): \(path)"
    } else {
        displayText = input.toolInputAsString
    }

    let cwd = input.cwd ?? FileManager.default.currentDirectoryPath

    // Set up NSApplication for the gate window
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    var wasApproved = false

    let gateWindow = GateWindow(
        ruleName: rule.name,
        riskLevel: rule.risk.rawValue,
        reason: rule.reason,
        commandText: displayText,
        workingDirectory: cwd
    )

    let auth = BiometricAuth()

    gateWindow.onAuthenticate = {
        auth.authenticate(reason: "claude-gate: \(rule.name)") { success, errorMessage in
            if success {
                wasApproved = true
                gateWindow.close()
                print(OutputDecision.approve(reason: "Authenticated via Touch ID").toJSON())
                app.stop(nil)
                // Post a dummy event to unblock the run loop
                let event = NSEvent.otherEvent(
                    with: .applicationDefined,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 0,
                    data1: 0,
                    data2: 0
                )
                if let event = event {
                    app.postEvent(event, atStart: true)
                }
            } else {
                gateWindow.showError(errorMessage ?? "Authentication failed")
            }
        }
    }

    gateWindow.onCancel = {
        FileHandle.standardError.write(Data("claude-gate: Authentication cancelled\n".utf8))
        print(OutputDecision.deny(reason: "Authentication cancelled").toJSON())
        app.stop(nil)
        let event = NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 0,
            data1: 0,
            data2: 0
        )
        if let event = event {
            app.postEvent(event, atStart: true)
        }
    }

    gateWindow.show()
    app.activate(ignoringOtherApps: true)
    app.run()

    exit(wasApproved ? 0 : 2)
}
