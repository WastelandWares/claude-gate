# Configurable Timeout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the gate window timeout configurable via rules.toml with a visual countdown timer and configurable default action on timeout.

**Architecture:** Add `timeout` and `timeout_action` fields to `[defaults]` in rules.toml. Parse them in RuleEngine. Add a countdown timer label to GateWindow that ticks every second. Wire a window-level timeout in main.swift that fires independently of BiometricAuth's internal timeout.

**Tech Stack:** Swift, AppKit (NSTextField for countdown, Timer for ticks), TOMLKit

---

### Task 1: Add timeout config to RuleEngine

**Files:**
- Modify: `Sources/claude-gate/RuleEngine.swift:1-57`
- Modify: `Config/default-rules.toml:1-8`

**Step 1: Add timeout properties to RuleEngine**

In `RuleEngine.swift`, add two new properties and parse them from `[defaults]`:

```swift
class RuleEngine {
    let defaultAction: RuleAction
    let rules: [Rule]
    let timeout: TimeInterval
    let timeoutAction: RuleAction

    init(configPath: String) throws {
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

        // Parse timeout (default 60 seconds)
        if let defaults = table["defaults"]?.table,
           let t = defaults["timeout"]?.int {
            self.timeout = TimeInterval(t)
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

        // ... rest of init unchanged (parse [[rules]])
```

**Step 2: Add timeout config to default-rules.toml**

Update the `[defaults]` section:

```toml
[defaults]
action = "passthrough"
timeout = 60           # seconds before auto-action on gate windows
timeout_action = "deny" # action when timeout expires: deny | passthrough
```

**Step 3: Build to verify compilation**

Run: `cd /Users/tquick/projects/claude-gate && swift build 2>&1`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/claude-gate/RuleEngine.swift Config/default-rules.toml
git commit -m "feat: parse timeout and timeout_action from rules.toml defaults"
```

---

### Task 2: Add countdown timer to GateWindow

**Files:**
- Modify: `Sources/claude-gate/GateWindow.swift`

**Step 1: Add countdown UI and timer to GateWindow**

Add these properties and modify the initializer:

```swift
class GateWindow: NSObject, NSWindowDelegate {
    var onAuthenticate: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTimeout: (() -> Void)?

    private let window: NSWindow
    private let errorLabel: NSTextField
    private let auditHeader: NSTextField
    private let auditLabel: NSTextField
    private let stackView: NSStackView
    private var resolved = false

    // Countdown
    private let countdownLabel: NSTextField
    private var remainingSeconds: Int
    private var countdownTimer: Timer?
```

In `init`, add a `timeout` parameter (default 60):

```swift
init(ruleName: String, riskLevel: String, reason: String, commandText: String, workingDirectory: String, justification: String? = nil, timeout: Int = 60) {
```

Create the countdown label after the risk label:

```swift
// Countdown timer
let countdownLabel = NSTextField(labelWithString: "Auto-deny in \(timeout)s")
countdownLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
countdownLabel.textColor = .secondaryLabelColor
self.countdownLabel = countdownLabel
self.remainingSeconds = timeout
```

Add `countdownLabel` to the stack view right after `riskLabel`:

```swift
stackView.addArrangedSubview(ruleLabel)
stackView.addArrangedSubview(riskLabel)
stackView.addArrangedSubview(countdownLabel)  // NEW
stackView.addArrangedSubview(separator)
```

**Step 2: Add timer start/stop methods**

```swift
func startCountdown() {
    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        self.remainingSeconds -= 1
        if self.remainingSeconds <= 0 {
            self.countdownTimer?.invalidate()
            self.countdownTimer = nil
            if !self.resolved {
                self.resolved = true
                self.onTimeout?()
                self.window.close()
            }
        } else {
            self.countdownLabel.stringValue = "Auto-deny in \(self.remainingSeconds)s"
            // Change color when running low
            if self.remainingSeconds <= 10 {
                self.countdownLabel.textColor = .systemOrange
            }
            if self.remainingSeconds <= 5 {
                self.countdownLabel.textColor = .systemRed
            }
        }
    }
}
```

Update the `close()` method to invalidate the timer:

```swift
func close() {
    resolved = true
    countdownTimer?.invalidate()
    countdownTimer = nil
    window.close()
}
```

Also update `cancelClicked` and `authenticateClicked` to invalidate the timer:

```swift
@objc private func cancelClicked() {
    resolved = true
    countdownTimer?.invalidate()
    countdownTimer = nil
    onCancel?()
    window.close()
}

@objc private func authenticateClicked() {
    resolved = true
    countdownTimer?.invalidate()
    countdownTimer = nil
    onAuthenticate?()
}
```

And `windowWillClose`:

```swift
func windowWillClose(_ notification: Notification) {
    countdownTimer?.invalidate()
    countdownTimer = nil
    if !resolved {
        resolved = true
        onCancel?()
    }
}
```

**Step 3: Update the countdown label text to reflect configured action**

Add a `timeoutActionLabel` parameter to init:

```swift
init(ruleName: String, riskLevel: String, reason: String, commandText: String, workingDirectory: String, justification: String? = nil, timeout: Int = 60, timeoutAction: String = "deny") {
```

Use it in the label:

```swift
let actionWord = timeoutAction == "passthrough" ? "Auto-allow" : "Auto-deny"
let countdownLabel = NSTextField(labelWithString: "\(actionWord) in \(timeout)s")
```

Store `actionWord` for the tick updates too (as a property).

**Step 4: Build to verify**

Run: `cd /Users/tquick/projects/claude-gate && swift build 2>&1`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add Sources/claude-gate/GateWindow.swift
git commit -m "feat: add visual countdown timer to gate window"
```

---

### Task 3: Wire timeout into main.swift

**Files:**
- Modify: `Sources/claude-gate/main.swift:107-154`

**Step 1: Pass timeout config to GateWindow and wire onTimeout**

Update the GateWindow construction to use engine's timeout config:

```swift
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
```

Add the onTimeout handler after the existing onCancel handler:

```swift
gateWindow.onTimeout = {
    switch engine.timeoutAction {
    case .passthrough:
        respond(output: .allow(reason: "Timeout — auto-approved by configuration"), exitCode: 0)
    case .deny, .gate:
        respond(output: .deny(reason: "Timeout — no response within \(timeoutSeconds)s"), exitCode: 0)
    }
}
```

Start the countdown after showing the window:

```swift
gateWindow.show()
gateWindow.startCountdown()
app.activate(ignoringOtherApps: true)
app.run()
```

**Step 2: Remove the BiometricAuth internal 60s timeout dependency**

The BiometricAuth timeout is separate from the window timeout. The window timeout handles the overall deadline. Keep BiometricAuth's timeout as-is for safety (belt and suspenders), but the window countdown is now the user-visible mechanism.

**Step 3: Build and test**

Run: `cd /Users/tquick/projects/claude-gate && swift build 2>&1`
Expected: Build succeeds

Run existing CI tests:
```bash
cd /Users/tquick/projects/claude-gate
mkdir -p ~/.config/claude-gate
cp Config/default-rules.toml ~/.config/claude-gate/rules.toml
BINARY=".build/debug/claude-gate"

echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | $BINARY 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['permissionDecision'] == 'allow'"
echo "PASS: passthrough still works"

echo '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' | $BINARY 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['permissionDecision'] == 'deny'"
echo "PASS: deny still works"
```

**Step 4: Commit**

```bash
git add Sources/claude-gate/main.swift
git commit -m "feat: wire configurable timeout with countdown into gate flow"
```

---

### Task 4: Add CI test for timeout config parsing

**Files:**
- Modify: `.github/workflows/ci.yml`

**Step 1: Add a test that verifies custom timeout config is accepted**

Add after the existing tests in ci.yml:

```yaml
          echo "--- Test: custom timeout config ---"
          cat > ~/.config/claude-gate/rules.toml << 'TOML'
          [defaults]
          action = "passthrough"
          timeout = 30
          timeout_action = "deny"

          [[rules]]
          name = "Block: system destruction"
          tool = "Bash"
          pattern = 'rm\s+(-[a-zA-Z]*f[a-zA-Z]*\s+|(-[a-zA-Z]*\s+)*)[/~]'
          action = "deny"
          reason = "Blocked"
          risk = "critical"
          TOML

          RESULT=$(echo '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}' | $BINARY 2>/dev/null)
          echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['hookSpecificOutput']['permissionDecision'] == 'allow', f'Expected allow, got {d}'"
          echo "PASS: custom timeout config accepted"

          # Restore default config
          cp Config/default-rules.toml ~/.config/claude-gate/rules.toml
```

**Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "test: add CI test for custom timeout config parsing"
```

---

### Task 5: Update README

**Files:**
- Modify: `README.md`

**Step 1: Add timeout configuration docs**

Add a section in the README explaining the new `[defaults]` fields:

```markdown
### Timeout Configuration

Configure how long the gate window waits before auto-acting:

```toml
[defaults]
action = "passthrough"
timeout = 60           # seconds before auto-action (default: 60)
timeout_action = "deny" # what to do on timeout: deny | passthrough (default: deny)
```

The gate window shows a visual countdown. When it reaches zero, the configured `timeout_action` is applied automatically.
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: document timeout configuration in README"
```
