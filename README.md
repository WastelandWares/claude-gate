# claude-gate

Biometric permission gating for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). Think `sudo` for AI — but with contextual explanations and Touch ID.

claude-gate intercepts Claude Code tool calls before execution, matches them against configurable rules, and gates dangerous ones behind Touch ID or password authentication.

```
Claude Code: "I'll run rm -rf /tmp/build"
        |
   claude-gate evaluates rules
        |
   Rule matched: "Gate: destructive command"
        |
   +------------------------------------------+
   | claude-gate: Authorization Required       |
   |                                           |
   | Rule: Gate: destructive command            |
   | Risk: HIGH                                 |
   |                                           |
   | WHY:                                       |
   | This command could remove important files. |
   |                                           |
   | COMMAND:                                   |
   | rm -rf /tmp/build                          |
   |                                           |
   |        [ Cancel ]   [ Authenticate ]       |
   +------------------------------------------+
        |
   Touch ID / Password prompt
        |
   Approved → Claude Code continues
```

## Install

Requires macOS 13+ (Ventura) and Swift 5.9+.

```bash
git clone https://github.com/severeon/claude-gate.git
cd claude-gate
./install.sh
```

This will:
1. Build the release binary
2. Copy it to `/usr/local/bin/claude-gate`
3. Seed default rules to `~/.config/claude-gate/rules.toml`

Then add the hook to `~/.claude/settings.json`:

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

## How It Works

claude-gate runs as a [Claude Code PreToolUse hook](https://docs.anthropic.com/en/docs/claude-code/hooks). Every time Claude Code is about to use a tool (run a command, write a file, etc.), claude-gate evaluates the action against your rules:

| Action | What happens |
|--------|-------------|
| **passthrough** | Silently approved. Claude Code continues. |
| **gate** | Native macOS window appears with explanation. Requires Touch ID or password to proceed. |
| **deny** | Hard block. Claude Code is told the action was denied. |

## Rules

Rules live in `~/.config/claude-gate/rules.toml`. They're evaluated top-to-bottom, first match wins (like firewall rules).

```toml
[defaults]
action = "passthrough"  # what to do when no rule matches

[[rules]]
name = "Hard block: system destruction"
tool = "Bash"
pattern = '(rm\s+-rf\s+[/~]|mkfs|dd\s+if=)'
action = "deny"
reason = "This command could destroy system-level files or devices."
risk = "critical"

[[rules]]
name = "Gate: force push"
tool = "Bash"
pattern = 'git\s+push\s+.*--force'
action = "gate"
reason = "Force-pushing rewrites remote history."
risk = "high"

[[rules]]
name = "Gate: package install"
tool = "Bash"
pattern = '(npm install|pip install|cargo install|brew install)'
action = "gate"
reason = "Installing packages pulls third-party code."
risk = "medium"
```

### Rule fields

| Field | Description |
|-------|-------------|
| `name` | Human-readable name shown in the gate window |
| `tool` | Claude Code tool to match: `Bash`, `Write`, `Edit`, or any MCP tool name |
| `pattern` | Regex tested against `tool_input.command` (Bash) or serialized input (MCP tools) |
| `path_pattern` | Regex tested against `tool_input.file_path` (Write/Edit tools) |
| `action` | `passthrough`, `gate`, or `deny` |
| `reason` | Explanation shown in the gate window |
| `risk` | `critical`, `high`, `medium`, or `low` — affects UI color coding |

### Default rules

The shipped defaults cover:
- **Deny:** `rm -rf /`, `mkfs`, `dd if=`, fork bombs
- **Gate:** force push, package installs, secrets/env access, dotfile modifications, network requests (curl, wget, ssh)
- **Passthrough:** everything else

## Authentication

claude-gate uses macOS `LocalAuthentication` framework with the `.deviceOwnerAuthentication` policy. This means:

1. **Touch ID** is tried first
2. **System password** is the automatic fallback (works on Macs without Touch ID)
3. **3 retries** before auto-deny
4. **60-second timeout** to prevent hanging Claude Code sessions

## Architecture

```
Claude Code PreToolUse hook
        |
        v
   claude-gate (Swift CLI)
        |
        +-- Read stdin JSON from Claude Code
        +-- Load rules from ~/.config/claude-gate/rules.toml
        +-- Evaluate: first matching rule wins
        |
        +-- passthrough → exit 0, stdout: {"decision":"approve"}
        +-- deny → exit 2, stdout: {"decision":"deny"}
        +-- gate → show NSWindow, require auth
                +-- auth success → exit 0, approve
                +-- auth fail/cancel → exit 2, deny
```

Built with:
- **Swift 5.9+** — native macOS frameworks, no FFI
- **AppKit** — native window, no Electron
- **LocalAuthentication** — Touch ID + password
- **TOMLKit** — TOML config parsing

## License

MIT
