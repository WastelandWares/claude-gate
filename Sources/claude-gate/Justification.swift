import Foundation

/// Asks Claude to explain why it needs to run a gated command,
/// using the session transcript for context.
class Justification {
    /// Request a justification asynchronously. Returns nil if unavailable (no API key).
    static func request(
        input: HookInput,
        ruleName: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let apiKey = ProcessInfo.processInfo.environment["CLAUDE_GATE_API_KEY"]
            ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] else {
            completion(nil)
            return
        }

        let transcriptContext = readTranscriptTail(path: input.transcriptPath, maxLines: 30)

        let commandDescription: String
        if let cmd = input.command {
            commandDescription = "Bash command: \(cmd)"
        } else if let path = input.filePath {
            commandDescription = "\(input.toolName) file: \(path)"
        } else {
            commandDescription = "\(input.toolName): \(input.toolInputAsString)"
        }

        let systemPrompt = """
        You are explaining to a user why an AI coding assistant needs to run a specific command. \
        The user has a security gate that requires approval before certain commands run. \
        They clicked "Why?" to understand the reasoning.

        Be concise (2-4 sentences). Explain:
        1. What the user asked for that led to this command
        2. Why this specific command is needed
        3. What would happen if it's denied

        Do NOT use markdown. Plain text only. Be direct and honest.
        """

        let userMessage = """
        The AI wants to run this tool call:
        \(commandDescription)

        Security rule triggered: \(ruleName)
        Working directory: \(input.cwd ?? "unknown")
        AI's description: \(input.toolDescription ?? "none provided")

        Recent conversation:
        \(transcriptContext)

        Explain why this command is needed in the context of what the user asked for.
        """

        callAPI(apiKey: apiKey, systemPrompt: systemPrompt, userMessage: userMessage, completion: completion)
    }

    // MARK: - Private

    private static func readTranscriptTail(path: String?, maxLines: Int) -> String {
        guard let path = path else { return "[no transcript available]" }

        let expandedPath = URL(fileURLWithPath: NSString(string: path).standardizingPath).resolvingSymlinksInPath().path
        let claudeDir = URL(fileURLWithPath: NSString(string: "~/.claude").expandingTildeInPath).resolvingSymlinksInPath().path
        guard expandedPath.hasPrefix(claudeDir) else {
            return "[transcript path outside expected directory]"
        }

        guard let data = FileManager.default.contents(atPath: expandedPath),
              let content = String(data: data, encoding: .utf8) else {
            return "[could not read transcript]"
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        let tail = lines.suffix(maxLines)

        var summary: [String] = []
        for line in tail {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let role = json["type"] as? String ?? "unknown"
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String, !text.isEmpty {
                        let truncated = text.count > 300 ? String(text.prefix(300)) + "..." : text
                        summary.append("[\(role)] \(truncated)")
                    }
                }
            }
        }

        return summary.isEmpty ? "[transcript empty]" : summary.joined(separator: "\n")
    }

    private static func callAPI(
        apiKey: String,
        systemPrompt: String,
        userMessage: String,
        completion: @escaping (String?) -> Void
    ) {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 256,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(nil)
            return
        }
        request.httpBody = bodyData

        let task = URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let firstBlock = content.first,
                  let text = firstBlock["text"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            DispatchQueue.main.async { completion(text) }
        }
        task.resume()
    }
}
