import Foundation
import AppKit

// Read all JSON from stdin (readDataToEndOfFile ensures we get everything)
let inputData = FileHandle.standardInput.readDataToEndOfFile()
guard !inputData.isEmpty else {
    // No input — allow (hook was invoked with nothing)
    print(HookOutput.allow(reason: "No input received").toJSON())
    exit(0)
}

// Parse hook input — fail-closed: deny if we can't parse
let input: HookInput
do {
    input = try JSONDecoder().decode(HookInput.self, from: inputData)
} catch {
    FileHandle.standardError.write(Data("claude-gate: Failed to parse input: \(error.localizedDescription)\n".utf8))
    print(HookOutput.deny(reason: "claude-gate: Failed to parse hook input").toJSON())
    exit(2)
}

// Load rules — fail-closed: deny if config is missing or broken
let configPath = NSString("~/.config/claude-gate/rules.toml").expandingTildeInPath
let engine: RuleEngine
do {
    engine = try RuleEngine(configPath: configPath)
} catch {
    FileHandle.standardError.write(Data("claude-gate: Failed to load rules from \(configPath): \(error.localizedDescription)\n".utf8))
    print(HookOutput.deny(reason: "claude-gate: Failed to load rules config").toJSON())
    exit(2)
}

// Configure voice
GateVoice.shared.configure(enabled: engine.voiceEnabled)

// Evaluate
let (matchedRule, action) = engine.evaluate(input)

switch action {
case .passthrough:
    let reason = matchedRule?.name ?? "No matching rule"
    AuditLog.shared.log(input: input, rule: matchedRule, action: .passthrough, decision: "allow", reason: reason)
    print(HookOutput.allow(reason: reason).toJSON())
    exit(0)

case .deny:
    let reason = matchedRule?.reason ?? "Denied by rule"
    AuditLog.shared.log(input: input, rule: matchedRule, action: .deny, decision: "deny", reason: reason)
    FileHandle.standardError.write(Data("claude-gate: DENIED — \(reason)\n".utf8))
    print(HookOutput.deny(reason: reason).toJSON())
    exit(0)

case .gate:
    guard let rule = matchedRule else {
        print(HookOutput.allow(reason: "No rule for gate action").toJSON())
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

    // Send OS notification (permission-safe: checks status before sending)
    GateNotification.shared.ensurePermission {
        GateNotification.shared.notify(ruleName: rule.name, riskLevel: rule.risk.rawValue, command: displayText)
    }

    // Guard against double output — only one response allowed
    var hasResponded = false
    let respondLock = NSLock()

    func respond(output: HookOutput, exitCode: Int32) {
        respondLock.lock()
        guard !hasResponded else {
            respondLock.unlock()
            return
        }
        hasResponded = true
        respondLock.unlock()

        print(output.toJSON())
        fflush(stdout)

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

        DispatchQueue.main.async {
            exit(exitCode)
        }
    }

    let timeoutSeconds = Int(engine.timeout)
    let timeoutActionStr = engine.timeoutAction == .passthrough ? "passthrough" : "deny"

    let gateWindow = GateWindow(
        ruleName: rule.name,
        riskLevel: rule.risk.rawValue,
        reason: rule.reason,
        commandText: displayText,
        workingDirectory: cwd,
        justification: input.toolDescription,
        timeout: timeoutSeconds,
        timeoutAction: timeoutActionStr
    )

    let auth = BiometricAuth()

    gateWindow.onAuthenticate = {
        auth.authenticate(reason: "claude-gate: \(rule.name)") { success, errorMessage in
            if success {
                gateWindow.close()
                AuditLog.shared.log(input: input, rule: rule, action: .gate, decision: "allow", reason: "Authenticated via Touch ID")
                respond(output: .allow(reason: "Authenticated via Touch ID"), exitCode: 0)
            } else {
                gateWindow.showError(errorMessage ?? "Authentication failed")
            }
        }
    }

    gateWindow.onCancel = {
        AuditLog.shared.log(input: input, rule: rule, action: .gate, decision: "deny", reason: "Authentication cancelled")
        respond(output: .deny(reason: "Authentication cancelled"), exitCode: 0)
    }

    gateWindow.onAlwaysAllow = {
        // Require biometric auth before creating a permanent passthrough rule
        auth.authenticate(reason: "claude-gate: Create permanent allow rule") { success, errorMessage in
            if success {
                gateWindow.close()
                let ruleSuccess = RuleWriter.addRule(
                    action: .passthrough,
                    toolName: input.toolName,
                    command: input.command,
                    filePath: input.filePath,
                    originalRuleName: rule.name
                )
                let reason = ruleSuccess
                    ? "Always allow rule created — command approved"
                    : "Failed to create rule — command approved this time"
                AuditLog.shared.log(input: input, rule: rule, action: .gate, decision: "allow", reason: reason)
                respond(output: .allow(reason: reason), exitCode: 0)
            } else {
                gateWindow.showError(errorMessage ?? "Authentication required to create permanent rule")
            }
        }
    }

    gateWindow.onAlwaysDeny = {
        // No auth needed to deny — denying is always safe
        let success = RuleWriter.addRule(
            action: .deny,
            toolName: input.toolName,
            command: input.command,
            filePath: input.filePath,
            originalRuleName: rule.name
        )
        let reason = success
            ? "Always deny rule created — command denied"
            : "Failed to create rule — command denied this time"
        AuditLog.shared.log(input: input, rule: rule, action: .gate, decision: "deny", reason: reason)
        respond(output: .deny(reason: reason), exitCode: 0)
    }

    gateWindow.onTimeout = {
        switch engine.timeoutAction {
        case .passthrough:
            AuditLog.shared.log(input: input, rule: rule, action: .gate, decision: "allow", reason: "Timeout — auto-approved by configuration")
            respond(output: .allow(reason: "Timeout — auto-approved by configuration"), exitCode: 0)
        case .deny, .gate:
            AuditLog.shared.log(input: input, rule: rule, action: .gate, decision: "deny", reason: "Timeout — no response within \(timeoutSeconds)s")
            respond(output: .deny(reason: "Timeout — no response within \(timeoutSeconds)s"), exitCode: 0)
        }
    }

    gateWindow.onRequestJustification = {
        Justification.request(input: input, ruleName: rule.name) { justification in
            respondLock.lock()
            let alreadyDone = hasResponded
            respondLock.unlock()
            guard !alreadyDone else { return }

            DispatchQueue.main.async {
                if let justification = justification {
                    gateWindow.showJustificationResponse(justification)
                } else {
                    gateWindow.showJustificationUnavailable()
                }
            }
        }
    }

    // Kick off security audit in background (non-blocking, opt-in)
    if engine.auditEnabled {
        SecurityAudit.run(input: input, ruleName: rule.name, ruleReason: rule.reason) { result in
            // Guard: don't update UI if the window has already been resolved
            respondLock.lock()
            let alreadyDone = hasResponded
            respondLock.unlock()
            guard !alreadyDone else { return }

            if let result = result {
                gateWindow.showAuditResult(verdict: result.verdict.rawValue, analysis: result.analysis)
            } else {
                gateWindow.showAuditUnavailable()
            }
        }
    } else {
        gateWindow.showAuditUnavailable()
    }

    gateWindow.show()
    gateWindow.startCountdown()
    GateVoice.shared.announceGate(ruleName: rule.name, riskLevel: rule.risk.rawValue, command: displayText)
    app.activate(ignoringOtherApps: true)
    app.run()

    // Fallback: if app.run() returns without respond() being called, deny cleanly
    respond(output: .deny(reason: "Gate window closed without decision"), exitCode: 0)
}
