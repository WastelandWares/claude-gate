import Foundation
import ClaudeGateCore

/// Caches gate approvals for a configurable grace period per rule.
/// Stores expiry timestamps in ~/.config/claude-gate/grace.json.
class GraceCache {
    static let shared = GraceCache()

    private let cachePath: String
    private var cache: [String: TimeInterval] = [:]

    private init() {
        cachePath = NSString("~/.config/claude-gate/grace.json").expandingTildeInPath
        load()
    }

    /// Check if a rule has a valid (non-expired) grace approval.
    func hasValidGrace(ruleName: String) -> Bool {
        guard let expiry = cache[ruleName] else { return false }
        if Date().timeIntervalSince1970 < expiry {
            return true
        }
        // Expired — remove it
        cache.removeValue(forKey: ruleName)
        save()
        return false
    }

    /// Record an approval with grace period.
    func recordApproval(ruleName: String, gracePeriod: TimeInterval) {
        guard gracePeriod > 0 else { return }
        cache[ruleName] = Date().timeIntervalSince1970 + gracePeriod
        save()
    }

    // MARK: - Private

    private func load() {
        guard let data = FileManager.default.contents(atPath: cachePath),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: TimeInterval] else {
            return
        }
        // Prune expired entries on load
        let now = Date().timeIntervalSince1970
        cache = dict.filter { $0.value > now }
    }

    private func save() {
        guard let data = try? JSONSerialization.data(withJSONObject: cache) else { return }
        FileManager.default.createFile(atPath: cachePath, contents: data)
    }
}
