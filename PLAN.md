# claude-gate: Biometric Permission Gating for Claude Code

## What This Is

A macOS CLI tool + Claude Code hook that intercepts blocked commands before execution, displays a native window explaining what/why/how, and requires Touch ID or password authentication to proceed. Think of it as `sudo` for Claude Code — but with contextual explanations and biometric proof-of-intent.

---

## Architecture Overview

Three components, connected as a pipeline:

```
Claude Code PreToolUse hook
        │
        │  stdin: JSON {tool_name, tool_input, ...}
        ▼
   claude-gate (Swift CLI binary)
        │
        ├─ Check against rule config (~/.config/claude-gate/rules.toml)
        │
        ├─ If no rule matches → exit 0, stdout: {"decision":"approve"} (passthrough)
        │
        ├─ If rule matches "deny" → exit 2, stderr: reason (hard block, no prompt)
        │
        └─ If rule matches "gate" →
              ├─ Spawn NSWindow with explanation panel
              ├─ Show: command text, rule reason, risk level
              ├─ Trigger LAContext biometric auth (Touch ID → password fallback)
              ├─ On success → exit 0, stdout: {"decision":"approve"}
              └─ On failure/cancel → exit 2, stderr: "Authentication denied"
```

---

## Component 1: Swift CLI Binary (`claude-gate`)

### Language & Frameworks

- **Swift 5.9+** (ships with macOS, no Xcode project needed — `swiftc` from command line)
- **LocalAuthentication.framework** — Touch ID / password
- **AppKit** — NSWindow for the explanation popup
- **Foundation** — JSON parsing, file I/O, process stdin

### Build

Single-target Swift Package Manager project. This keeps it clean for distribution and testability while staying compilable via `swift build --configuration release`. No Xcode project file.

```
claude-gate/
├── Package.swift
├── Sources/
│   └── claude-gate/
│       ├── main.swift              # Entry point: read stdin, dispatch
│       ├── HookInput.swift         # Codable struct for Claude Code JSON
│       ├── RuleEngine.swift        # TOML config parsing + matching
│       ├── Rule.swift              # Rule model (pattern, action, reason, risk)
│       ├── GateWindow.swift        # NSWindow subclass for the explanation UI
│       ├── BiometricAuth.swift     # LAContext wrapper
│       └── OutputDecision.swift    # Codable response structs
├── Config/
│   └── default-rules.toml         # Ships with sane defaults
├── install.sh                     # Build + copy binary + seed config
└── README.md
```

### stdin Contract (from Claude Code)

Claude Code sends JSON to PreToolUse hooks on stdin. Key fields:

```json
{
  "session_id": "...",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf ./dist"
  },
  "cwd": "/Users/thomas/projects/neuroscript",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse"
}
```

The binary must also handle `tool_name` values beyond `Bash`:
- `Write` (file writes — `tool_input.file_path`)
- `Edit` (file edits — `tool_input.file_path`)  
- MCP tool names (e.g., `mcp__uuid__toolName`)

### stdout Contract (back to Claude Code)

Approve:
```json
{"decision": "approve", "reason": "Authenticated via Touch ID"}
```

Block:
```json
{"decision": "deny", "reason": "Hard-blocked: destructive system command"}
```

Exit codes: `0` = success (decision in stdout), `2` = blocking error.

---

## Component 2: Rule Configuration

### Format: TOML

TOML is the right call here — it's human-readable, comment-friendly, and there's a mature Swift TOML parser (`TOMLKit` via SPM). Lives at `~/.config/claude-gate/rules.toml`.

### Rule Schema

```toml
# Default action when no rule matches
[defaults]
action = "passthrough"  # passthrough | gate | deny

# Rules evaluated top-to-bottom, first match wins

[[rules]]
name = "Hard block: system destruction"
tool = "Bash"
pattern = '(rm\s+-rf\s+[/~]|mkfs|dd\s+if=|:()\{)'  # regex against tool_input.command
action = "deny"
reason = "This command could destroy system-level files or devices."
risk = "critical"

[[rules]]
name = "Gate: force push"
tool = "Bash"
pattern = 'git\s+push\s+.*--force'
action = "gate"
reason = "Force-pushing rewrites remote history. Other contributors' work may be lost."
risk = "high"

[[rules]]
name = "Gate: package install"
tool = "Bash"
pattern = '(npm install|pip install|cargo install|brew install)'
action = "gate"
reason = "Installing packages modifies your system environment and pulls third-party code."
risk = "medium"

[[rules]]
name = "Gate: env/secrets access"
tool = "Bash"
pattern = '(\.env|secrets|credentials|password|api.?key)'
action = "gate"
reason = "This command may read or expose sensitive credentials."
risk = "high"

[[rules]]
name = "Gate: writes to home directory dotfiles"
tool = "Write"
path_pattern = '^\.(bash|zsh|ssh|gnupg|config)'  # regex against tool_input.file_path (relative to ~)
action = "gate"
reason = "Modifying dotfiles changes your shell environment and security configuration."
risk = "high"

[[rules]]
name = "Gate: network requests"
tool = "Bash"
pattern = '(curl|wget|nc\s|ncat|ssh\s)'
action = "gate"
reason = "This command initiates a network connection."
risk = "medium"
```

### Matching Logic (RuleEngine)

1. Parse all rules at startup (fail fast on bad config)
2. For each incoming hook event:
   - Filter rules where `rule.tool` matches `tool_name`
   - For matching rules, test `pattern` (regex) against the relevant field:
     - `Bash` → `tool_input.command`
     - `Write`/`Edit` → `tool_input.file_path`
     - MCP tools → `tool_input` serialized as string (catch-all)
   - If `path_pattern` is present, test against file path instead
   - First match wins
   - No match → use `defaults.action`

---

## Component 3: Gate Window (the popup)

### Design

Native `NSWindow`, no web views, no Electron. Minimal and informative.

```
┌─────────────────────────────────────────────────┐
│  ⚠️  claude-gate: Authorization Required         │
├─────────────────────────────────────────────────┤
│                                                 │
│  Rule:   Gate: force push                       │
│  Risk:   ██████░░ HIGH                          │
│                                                 │
│  WHY:                                           │
│  Force-pushing rewrites remote history.         │
│  Other contributors' work may be lost.          │
│                                                 │
│  EXACT COMMAND:                                 │
│  ┌────────────────────────────────────────────┐ │
│  │ git push --force origin main               │ │
│  └────────────────────────────────────────────┘ │
│                                                 │
│  WORKING DIRECTORY:                             │
│  /Users/thomas/projects/neuroscript             │
│                                                 │
│         [ Cancel ]        [ Authenticate 🔐 ]   │
│                                                 │
└─────────────────────────────────────────────────┘
```

### Behavior

- Window appears centered, always-on-top (`NSWindow.Level.floating`)
- "Authenticate" button triggers `LAContext.evaluatePolicy(.deviceOwnerAuthentication, ...)` — this uses Touch ID first, falls back to system password automatically (the `.deviceOwnerAuthentication` policy, NOT `.deviceOwnerAuthenticationWithBiometrics`, ensures password fallback)
- Cancel → exit 2
- Auth success → exit 0 with approve JSON
- Auth failure → show inline error, allow retry (up to 3 attempts), then exit 2
- 60-second timeout → auto-deny (prevents hanging Claude Code sessions)

### NSApplication Lifecycle

The binary needs a brief `NSApplication` run loop to drive the window and async auth callback. Pattern:

```swift
// Pseudocode — not production, just the shape
let app = NSApplication.shared
app.setActivationPolicy(.accessory)  // No dock icon
// ... create and show window ...
app.activate(ignoringOtherApps: true)
app.run()
// Call app.stop() from the auth completion handler
```

Use `.accessory` activation policy so it doesn't clutter the dock.

---

## Component 4: Claude Code Hook Wiring

### Installation Target

`~/.claude/settings.json` (user-level, applies to all projects):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/local/bin/claude-gate"
          }
        ]
      }
    ]
  }
}
```

Using `"matcher": "*"` catches all tools. The rule engine inside `claude-gate` handles the filtering — this keeps the hook config simple and all logic centralized in the TOML.

### Alternative: Scoped Matchers

If performance is a concern (spawning a process on every tool call), you can scope the matcher to only the tools you care about:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "/usr/local/bin/claude-gate" }]
      },
      {
        "matcher": "Write",
        "hooks": [{ "type": "command", "command": "/usr/local/bin/claude-gate" }]
      }
    ]
  }
}
```

---

## Install Script (`install.sh`)

```bash
#!/bin/bash
set -euo pipefail

echo "Building claude-gate..."
swift build --configuration release

BINARY=".build/release/claude-gate"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="$HOME/.config/claude-gate"

echo "Installing binary to $INSTALL_DIR..."
sudo cp "$BINARY" "$INSTALL_DIR/claude-gate"
sudo chmod +x "$INSTALL_DIR/claude-gate"

echo "Seeding default config..."
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_DIR/rules.toml" ]; then
  cp Config/default-rules.toml "$CONFIG_DIR/rules.toml"
  echo "Created $CONFIG_DIR/rules.toml — edit to customize."
else
  echo "$CONFIG_DIR/rules.toml already exists, skipping."
fi

echo ""
echo "Add this to ~/.claude/settings.json:"
echo '  "hooks": {'
echo '    "PreToolUse": [{'
echo '      "matcher": "*",'
echo '      "hooks": [{"type": "command", "command": "/usr/local/bin/claude-gate"}]'
echo '    }]'
echo '  }'
echo ""
echo "Done."
```

---

## Implementation Order

Build in this sequence — each step is independently testable:

### Phase 1: Stdin/Stdout Plumbing (est. 30 min)
- `HookInput.swift` — Codable model for Claude Code's JSON
- `OutputDecision.swift` — response structs
- `main.swift` — read stdin, parse, hard-code approve, write stdout
- **Test:** pipe sample JSON, verify passthrough works

### Phase 2: Rule Engine (est. 1 hr)
- `Rule.swift` — model with regex patterns
- `RuleEngine.swift` — TOML parsing (use `TOMLKit` via SPM), matching logic
- `default-rules.toml` — ship with the rules above
- **Test:** unit tests with sample inputs against each rule type

### Phase 3: Biometric Auth (est. 30 min)
- `BiometricAuth.swift` — `LAContext` wrapper, async → callback
- Handles: Touch ID success, Touch ID failure, password fallback, no biometrics available, timeout
- **Test:** standalone invocation from terminal

### Phase 4: Gate Window UI (est. 1-2 hrs)
- `GateWindow.swift` — `NSWindow` with labels, command display, buttons
- Wire "Authenticate" button to `BiometricAuth`
- Wire "Cancel" to exit 2
- `NSApplication` run loop lifecycle (`.accessory` policy, `app.stop()` on completion)
- Risk level color coding (critical=red, high=orange, medium=yellow)
- **Test:** invoke with sample gated command, verify window appears and auth flow works

### Phase 5: Integration + Install (est. 30 min)
- `install.sh`
- Wire into `~/.claude/settings.json`
- End-to-end test: run Claude Code, trigger a gated command, verify popup + auth

---

## Dependencies (SPM)

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "claude-gate",
    platforms: [.macOS(.v13)],  // Ventura+ for modern LAContext APIs
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "claude-gate",
            dependencies: ["TOMLKit"],
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("AppKit"),
            ]
        ),
        .testTarget(
            name: "claude-gate-tests",
            dependencies: ["claude-gate"]
        ),
    ]
)
```

---

## Future Considerations (Out of Scope for V1)

- **Grace windows**: After authenticating for a rule, cache approval for N minutes (store in Keychain with TTL). This is the MUCUS exponential decay connection — critical commands always re-auth, medium commands get a 5-min window.
- **Audit log**: Append every gate decision (approve/deny/timeout) to `~/.config/claude-gate/audit.jsonl` with timestamp, rule name, command, and auth method.
- **`claude-gate add` subcommand**: Interactive rule creation from CLI (`claude-gate add --tool Bash --pattern "docker rm" --risk medium`).
- **Rule testing mode**: `claude-gate test < sample.json` to dry-run rules without auth.
- **Linux support**: Replace `LAContext` with `polkit`/`pkexec` or `systemd-ask-password` for password-based gating. No biometrics equivalent on most Linux, but password confirmation still adds friction.

---

## Key Design Decisions & Rationale

1. **Swift, not Rust/Node**: `LocalAuthentication` and `AppKit` are Objective-C frameworks. Swift calls them natively with zero FFI friction. Rust would need `objc` crate bindings, and Node would need a native addon — both add complexity for no gain.

2. **TOML, not JSON/YAML**: Rules need inline comments explaining *why* a pattern exists. TOML supports this natively. JSON doesn't support comments. YAML is a footgun.

3. **`.deviceOwnerAuthentication`, not `.deviceOwnerAuthenticationWithBiometrics`**: The non-biometrics-specific policy falls back to system password automatically. Users without Touch ID (external keyboards, Mac Minis) can still use the tool.

4. **PreToolUse, not PermissionRequest**: `PermissionRequest` fires only when Claude *would* have prompted — if the user has already allowed the tool, it never fires. `PreToolUse` fires on *every* invocation, which is what we want for security gating.

5. **First-match-wins rule evaluation**: Same mental model as firewall rules, `.gitignore`, nginx location blocks. Predictable, debuggable.

6. **60-second timeout**: Claude Code hooks that don't respond will hang the session. Better to auto-deny than leave things in limbo.