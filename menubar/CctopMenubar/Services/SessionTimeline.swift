import Foundation

/// One line of a session's board timeline: what the user asked, or what the agent did.
struct TimelineEntry: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case agent
    }

    let id: String
    let role: Role
    let text: String
}

/// One user request and the agent's reply to it, as read from a transcript.
struct TimelineRound: Equatable {
    /// The user's own message; nil when the round starts with agent text (a resumed session).
    var prompt: String?
    /// The agent's latest text in this round.
    var reply: String?
    /// From the reply's summary line, when the agent wrote one.
    var asked: String?
    var did: String?

    mutating func takeReply(_ text: String) {
        reply = text
        guard let line = TurnSummaryLine.parse(text) else { return }
        did = line.did
        // A wake-up reply ("no new request") keeps what the user asked earlier in the round.
        if !TurnSummaryLine.isNoNewRequest(line.asked) || asked == nil {
            asked = line.asked
        }
    }
}

enum SessionTimeline {
    /// Board lines for the rounds, oldest first. The summary line wins; otherwise the
    /// first sentence of the raw text stands in.
    static func entries(from rounds: [TimelineRound]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        for (index, round) in rounds.enumerated() {
            if let asked = round.asked, !TurnSummaryLine.isNoNewRequest(asked) {
                entries.append(TimelineEntry(id: "\(index)u", role: .user, text: asked))
            } else if let prompt = round.prompt.flatMap({ TimelineText.brief($0) }) {
                entries.append(TimelineEntry(id: "\(index)u", role: .user, text: prompt))
            }
            if let did = round.did {
                entries.append(TimelineEntry(id: "\(index)a", role: .agent, text: did))
            } else if let reply = round.reply.flatMap({ TimelineText.brief($0) }) {
                entries.append(TimelineEntry(id: "\(index)a", role: .agent, text: reply))
            }
        }
        return entries
    }
}

/// The line each agent ends a reply with: `本轮｜你要：…｜我做：…`.
enum TurnSummaryLine {
    private static let pattern = try? NSRegularExpression(
        pattern: #"本轮\s*[｜|]\s*你要\s*[：:]\s*(.+?)\s*[｜|]\s*我做\s*[：:]\s*(.+)"#
    )
    private static let decoration = CharacterSet(charactersIn: "`*_>#-—– \t")

    /// Reads the summary from the reply's last few non-empty lines, nearest the end first.
    static func parse(_ reply: String) -> (asked: String, did: String)? {
        guard let pattern else { return nil }
        let lines = reply.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: decoration) }
            .filter { !$0.isEmpty }
        for line in lines.suffix(3).reversed() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let askedRange = Range(match.range(at: 1), in: line),
                  let didRange = Range(match.range(at: 2), in: line) else { continue }
            let asked = line[askedRange].trimmingCharacters(in: decoration)
            let did = line[didRange].trimmingCharacters(in: decoration)
            guard !asked.isEmpty, !did.isEmpty else { continue }
            return (asked, did)
        }
        return nil
    }

    static func isNoNewRequest(_ asked: String) -> Bool {
        asked.hasPrefix("无新要求")
    }
}

enum TimelineText {
    static let briefLimit = 40

    /// The first readable line of a message, without markdown or tag wrappers, cut at its
    /// first sentence end and capped at `limit` characters.
    static func brief(_ text: String, limit: Int = briefLimit) -> String? {
        var inFence = false
        var heading: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            if inFence || line.isEmpty || line.hasPrefix("<") || line.hasPrefix("|") { continue }
            let cleaned = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "#>-*• \t"))
            guard !cleaned.isEmpty else { continue }
            // A heading or a bare link names something; the first sentence after it says more.
            if line.hasPrefix("#") || (cleaned.hasPrefix("http") && !cleaned.contains(" ")) {
                heading = heading ?? cleaned
                continue
            }
            return truncated(firstSentence(cleaned), limit: limit)
        }
        return heading.map { truncated($0, limit: limit) }
    }

    private static func firstSentence(_ line: String) -> String {
        guard let end = line.firstIndex(where: { "。！？".contains($0) }) else { return line }
        let sentence = String(line[...end])
        // A very short lead-in ("好。") says little; keep the line instead.
        return sentence.count >= 6 ? sentence : line
    }

    private static func truncated(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
}

// MARK: - Transcript parsing

/// Builds rounds from transcript lines fed in file order. Feeding is incremental: a parser
/// keeps its state between reads of a growing file.
protocol TimelineTranscriptParser {
    var rounds: [TimelineRound] { get }
    mutating func consume(line: Data)
}

extension TimelineTranscriptParser {
    static func appendPrompt(_ prompt: String, to rounds: inout [TimelineRound]) {
        // A message sent before the agent replied (interrupted, or queued) joins the open round.
        if var last = rounds.last, last.reply == nil, let earlier = last.prompt {
            last.prompt = earlier + "\n" + prompt
            rounds[rounds.count - 1] = last
        } else {
            rounds.append(TimelineRound(prompt: prompt))
        }
    }

    static func appendReply(_ reply: String, to rounds: inout [TimelineRound]) {
        if rounds.isEmpty { rounds.append(TimelineRound()) }
        rounds[rounds.count - 1].takeReply(reply)
    }

    static func json(_ line: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: line) as? [String: Any]
    }

    static func joinedText(_ content: Any?, blockType: String = "text") -> String {
        if let text = content as? String { return text }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block in
            block["type"] as? String == blockType ? block["text"] as? String : nil
        }.joined(separator: "\n")
    }
}

/// Claude Code transcript JSONL (`~/.claude/projects/<dir>/<session>.jsonl`).
struct ClaudeTranscriptParser: TimelineTranscriptParser {
    private(set) var rounds: [TimelineRound] = []
    /// A resumed session copies earlier rows into its new file under the same uuid.
    private var seenUUIDs: Set<String> = []

    private static let userMarker = Data(#""type":"user""#.utf8)
    private static let assistantMarker = Data(#""type":"assistant""#.utf8)
    private static let textMarker = Data(#""type":"text""#.utf8)
    private static let toolResultMarker = Data(#""tool_result""#.utf8)
    private static let skippedPrefixes = [
        "<task-notification>", "<local-command", "<command-name>", "<command-message>",
        "[Request interrupted", "This session is being continued", "Caveat:",
    ]

    mutating func consume(line: Data) {
        // Most rows are tool calls and results; skip them before parsing JSON.
        let isUser = line.range(of: Self.userMarker) != nil && line.range(of: Self.toolResultMarker) == nil
        let isAssistant = !isUser && line.range(of: Self.assistantMarker) != nil
            && line.range(of: Self.textMarker) != nil
        guard isUser || isAssistant, let row = Self.json(line) else { return }
        if let uuid = row["uuid"] as? String {
            guard seenUUIDs.insert(uuid).inserted else { return }
        }
        if row["isSidechain"] as? Bool == true || row["isMeta"] as? Bool == true { return }
        let message = row["message"] as? [String: Any]

        switch row["type"] as? String {
        case "user":
            guard row["isCompactSummary"] as? Bool != true else { return }
            if let origin = row["origin"] as? [String: Any],
               let kind = origin["kind"] as? String, kind != "human" { return }
            let text = Self.joinedText(message?["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !Self.skippedPrefixes.contains(where: { text.hasPrefix($0) }) else { return }
            Self.appendPrompt(text, to: &rounds)
        case "assistant":
            let text = Self.joinedText(message?["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Self.appendReply(text, to: &rounds)
        default:
            return
        }
    }
}

/// Codex rollout JSONL (`~/.codex/sessions/YYYY/MM/DD/rollout-…-<thread>.jsonl`).
struct CodexRolloutParser: TimelineTranscriptParser {
    private(set) var rounds: [TimelineRound] = []

    private static let userMessageMarker = Data(#""UserMessage""#.utf8)
    private static let assistantMarker = Data(#""role":"assistant""#.utf8)
    private static let taskCompleteMarker = Data(#""task_complete""#.utf8)

    mutating func consume(line: Data) {
        guard line.range(of: Self.userMessageMarker) != nil
            || line.range(of: Self.assistantMarker) != nil
            || line.range(of: Self.taskCompleteMarker) != nil,
            let row = Self.json(line),
            let payload = row["payload"] as? [String: Any] else { return }

        switch (row["type"] as? String, payload["type"] as? String) {
        case ("event_msg", "item_completed"):
            // The user's own message; context Codex injects arrives as plain response items.
            guard let item = payload["item"] as? [String: Any],
                  item["type"] as? String == "UserMessage" else { return }
            let text = Self.joinedText(item["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Self.appendPrompt(text, to: &rounds)
        case ("response_item", "message"):
            guard payload["role"] as? String == "assistant" else { return }
            let text = Self.joinedText(payload["content"], blockType: "output_text")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            Self.appendReply(text, to: &rounds)
        case ("event_msg", "task_complete"):
            guard let text = (payload["last_agent_message"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            Self.appendReply(text, to: &rounds)
        default:
            return
        }
    }
}
