# claude-gate Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a macOS CLI that intercepts Claude Code tool calls, matches them against configurable rules, and gates dangerous ones behind Touch ID / password authentication.

**Architecture:** Swift CLI reads JSON from stdin (Claude Code PreToolUse hook), evaluates against TOML rules, and either passes through, hard-denies, or spawns an NSWindow requiring biometric auth before approving. Three exit paths: passthrough (exit 0, approve), gate (exit 0 after auth, or exit 2 on deny), hard-deny (exit 2).

**Tech Stack:** Swift 5.9+, SPM, AppKit, LocalAuthentication, TOMLKit

---

### Task 1: Package.swift + Project Scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/claude-gate/main.swift` (stub)

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "claude-gate",
    platforms: [.macOS(.v13)],
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
    ]
)
```

**Step 2: Create stub main.swift**

```swift
import Foundation
print("{\"decision\": \"approve\", \"reason\": \"stub\"}")
```

**Step 3: Verify it builds**

Run: `cd /Users/tquick/projects/claude-gate && swift build 2>&1`
Expected: BUILD SUCCEEDED

---

### Task 2: HookInput + OutputDecision Models

**Files:**
- Create: `Sources/claude-gate/HookInput.swift`
- Create: `Sources/claude-gate/OutputDecision.swift`

**HookInput.swift** - Codable model for Claude Code's stdin JSON
**OutputDecision.swift** - Response structs for stdout

---

### Task 3: Rule Model + RuleEngine

**Files:**
- Create: `Sources/claude-gate/Rule.swift`
- Create: `Sources/claude-gate/RuleEngine.swift`
- Create: `Config/default-rules.toml`

**Rule.swift** - Model with tool, pattern, path_pattern, action, reason, risk
**RuleEngine.swift** - TOML parsing via TOMLKit, first-match-wins evaluation

---

### Task 4: BiometricAuth

**Files:**
- Create: `Sources/claude-gate/BiometricAuth.swift`

LAContext wrapper with Touch ID + password fallback, 3 retry limit, 60s timeout.

---

### Task 5: GateWindow UI

**Files:**
- Create: `Sources/claude-gate/GateWindow.swift`

NSWindow with rule name, risk level, reason, command display, cancel/authenticate buttons.
NSApplication .accessory policy, floating window level, app.stop() on completion.

---

### Task 6: Main.swift Orchestration

**Files:**
- Modify: `Sources/claude-gate/main.swift`

Read stdin, parse HookInput, run RuleEngine, dispatch: passthrough/deny/gate.
For gate: spawn NSApplication, show GateWindow, run biometric auth.

---

### Task 7: install.sh + Integration

**Files:**
- Create: `install.sh`

Build, copy binary, seed config, print hook JSON for settings.

---
