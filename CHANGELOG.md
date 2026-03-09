# Changelog

All notable changes to claude-gate are documented here.

## [v0.8.0] - 2026-03-09

### Added
- **Production SSH gating**: SSH to `turtles-admin` always requires authentication with `grace_period = 0` (no cached approval). Rule placed before generic SSH rule for first-match priority. Risk level: critical. (#12)
- **Demo CLI tool**: `demo.sh` script with 13 test scenarios (force-push, env-file, ssh-production, ssh-generic, pip-install, npm-install, sudo, write-dotfile, hard-reset, curl-pipe, fork-bomb, rm-rf, deploy). Interactive menu or direct `./demo.sh [scenario]` invocation. (#14)
- **Separate API key**: `CLAUDE_GATE_API_KEY` environment variable for project-specific Anthropic API key, separate from the main `ANTHROPIC_API_KEY`. (#13)

## [v0.7.0] - 2026-03-08

### Added
- **Grace windows**: After authenticating for a gate rule, approval can be cached for a configurable period. Add `grace_period = 300` (seconds) to any rule in rules.toml. Default is 0 (always re-auth). Grace cache stored in `~/.config/claude-gate/grace.json`. (#5)

## [v0.6.0] - 2026-03-08

### Added
- **Unit tests**: 27 XCTest cases covering rule evaluation, path pattern matching, first-match-wins, timeout clamping, config parsing, malformed config handling, fail-closed behavior, and HookInput/HookOutput serialization. (#6)
- **Library target**: Extracted core types (RuleEngine, Rule, HookInput, HookOutput) into `ClaudeGateCore` library target for testability.
- **CI unit tests**: `swift test` now runs in CI alongside integration tests.

## [v0.5.1] - 2026-03-08

### Fixed
- **Release workflow**: Fixed heredoc causing backticks in release notes to be executed as commands. Curl and JSON settings were being run instead of used as text.

## [v0.5.0] - 2026-03-08

### Changed
- **Audit is now opt-in**: Security audit disabled by default. Enable with `audit = true` in `[defaults]` section of rules.toml. Previously, audit ran automatically whenever `ANTHROPIC_API_KEY` was set. (#3)
- **Separate API key support**: `CLAUDE_GATE_API_KEY` env var is checked first, falling back to `ANTHROPIC_API_KEY`. Applies to both security audit and justification features. (#3)

## [v0.4.2] - 2026-03-08

### Changed
- **Audit verdict disclaimer**: Added "AI audit is advisory only — verify commands yourself" below audit results. Changed SAFE verdict color from green to blue to avoid false sense of security. (#2)

## [v0.4.1] - 2026-03-08

### Fixed
- **Symlink resolution in transcript path validation**: Both `SecurityAudit.swift` and `Justification.swift` now resolve symlinks before validating that transcript paths are within `~/.claude/`. Previously, a symlink inside `~/.claude/` pointing elsewhere could bypass the path check. (#7)

## [v0.4.0] - 2026-03-08

### Added
- **Voice announcements**: Optional text-to-speech for gate events using macOS NSSpeechSynthesizer. Reads the rule name, risk level, and command aloud when a gate window appears. Enable with `voice = true` in `[defaults]` section of rules.toml. Disabled by default. (#16)

## [v0.3.0] - 2026-03-08

### Added
- **"Why?" justification button**: Gate window now includes a "Why?" button that asks Claude to explain why the intercepted command is needed. Uses session transcript context to provide a concise, plain-text explanation (2-4 sentences). Requires `ANTHROPIC_API_KEY`. (#15)

## [v0.2.0] - 2026-03-08

### Added
- **Configurable timeout**: `timeout` and `timeout_action` fields in `[defaults]` section of rules.toml. Visual countdown timer in the gate window changes color as time runs low (orange at 10s, red at 5s). Minimum bounds enforced (5s general, 30s for passthrough auto-approve). (#11)
- **Audit logging**: Every decision (passthrough, deny, gate approve/deny/timeout) is appended to `~/.config/claude-gate/audit.jsonl` with timestamp, session ID, tool name, command, matched rule, and risk level. Thread-safe writes with stderr warnings on failure. (#13, #4)
- **Persistent approval rules**: "Always Allow" and "Always Deny" buttons in the gate window. Creates permanent rules in rules.toml with exact-match patterns. Always Allow requires Touch ID authentication. Rules are inserted at top for first-match-wins priority. (#12)
- **OS notifications**: macOS notification via UserNotifications framework when a gate window appears. Shows rule name, risk level, and command. Clicking the notification brings the gate window to front. (#10)

## [v0.1.0] - 2026-03-07

### Added
- Initial release
- Rule engine with TOML config (first-match-wins evaluation)
- BiometricAuth with Touch ID + password fallback (3 retries, 60s timeout)
- Native macOS gate window (AppKit) with rule info, risk level, agent justification
- Security audit via Anthropic API (Claude Haiku)
- 50+ default rules covering system destruction, git, packages, credentials, network, docker, CI/CD
- Fail-closed security (bad JSON, missing config = deny)
- CI workflow with rule engine tests
- Release workflow for self-hosted macOS builds
