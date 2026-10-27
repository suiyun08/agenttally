import Foundation

/// What the Feishu bridge (`lark-channel-bridge`) records about the conversations it runs: which
/// bots run now, and which Feishu chat holds each conversation. The bridge starts one short-lived
/// client process per message, so between messages a bridge conversation has no process of its
/// own; its bot running and still holding it is the evidence that it goes on. Read-only: the
/// bridge owns these files.
final class LarkBridgeLookup {
    /// A bot that restarts keeps its conversations live for this long while it is down.
    static let restartGrace: TimeInterval = 600
    static let live = LarkBridgeLookup(home: defaultHome)
    static var defaultHome: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".lark-channel")
    }

    private let home: URL
    private let processStartTime: (Int32) -> TimeInterval?
    private var lastRunning: [String: Date] = [:]

    init(
        home: URL,
        processStartTime: @escaping (Int32) -> TimeInterval? = { SessionData.processStartTime(pid: UInt32($0)) }
    ) {
        self.home = home
        self.processStartTime = processStartTime
    }

    /// The bots running now or within the restart grace, and the conversations each holds.
    func snapshot(now: Date) -> LarkBridgeSnapshot {
        for profile in runningProfiles() { lastRunning[profile] = now }
        let live = lastRunning.filter { now.timeIntervalSince($0.value) <= Self.restartGrace }.keys
        return LarkBridgeSnapshot(scopes: Dictionary(uniqueKeysWithValues: live.map {
            ($0, Self.scopes(home: home, profile: $0))
        }))
    }

    /// The Feishu chat and topic holding a conversation, read afresh for a jump.
    static func chat(profile: String, conversationID: String, home: URL = defaultHome) -> LarkChat? {
        scopes(home: home, profile: profile)[conversationID].flatMap(LarkChat.init(scope:))
    }

    /// Session files are user-writable, so a profile name only reaches a path as a plain token.
    static func isProfileName(_ value: String) -> Bool {
        (1...64).contains(value.count)
            && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Profiles whose registered bridge process still runs. A PID that started after the bridge
    /// registered belongs to another process.
    private func runningProfiles() -> [String] {
        let url = home.appendingPathComponent("registry/processes.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["entries"] as? [[String: Any]] else { return [] }
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return entries.compactMap { entry in
            guard let profile = entry["profileName"] as? String, Self.isProfileName(profile),
                  let pid = (entry["pid"] as? NSNumber)?.int32Value, pid > 1,
                  let started = processStartTime(pid) else { return nil }
            if let registered = (entry["startedAt"] as? String).flatMap(dates.date(from:)),
               started > registered.timeIntervalSince1970 + 5 { return nil }
            return profile
        }
    }

    /// Conversation ID (Claude session or Codex thread) → the chat or topic scope that holds it,
    /// from the profile's session map and its catalog of resumable conversations.
    private static func scopes(home: URL, profile: String) -> [String: String] {
        guard isProfileName(profile) else { return [:] }
        let dir = home.appendingPathComponent("profiles/\(profile)")
        var scopes: [String: String] = [:]
        func conversationID(_ entry: [String: Any]) -> String? {
            (entry["sessionId"] as? String) ?? (entry["threadId"] as? String)
        }
        if let catalog = json(dir.appendingPathComponent("sessions.json.catalog.json")) as? [[String: Any]] {
            for entry in catalog where (entry["status"] as? String ?? "active") == "active" {
                if let id = conversationID(entry), let scope = entry["scopeId"] as? String { scopes[id] = scope }
            }
        }
        if let current = json(dir.appendingPathComponent("sessions.json")) as? [String: Any] {
            for (scope, value) in current {
                if let entry = value as? [String: Any], let id = conversationID(entry) { scopes[id] = scope }
            }
        }
        return scopes
    }

    private static func json(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

/// The Feishu bridge's conversations at one moment, for the bots that are live.
struct LarkBridgeSnapshot {
    static let empty = LarkBridgeSnapshot(scopes: [:])

    /// Profile → conversation ID → the chat or topic scope that holds it.
    let scopes: [String: [String: String]]

    /// Whether the session's bot is live and still holds its conversation.
    func holds(_ session: SessionData) -> Bool {
        guard let profile = session.larkChannelProfile, let held = scopes[profile] else { return false }
        return held[session.harnessSessionId ?? session.sessionId] != nil
    }
}

/// Where a bridge conversation lives in Feishu: a group chat (`oc_…`), and the topic in it
/// (`omt_…`) when the bot answers in one. The bridge's scope is `oc_…` or `oc_…:omt_…`.
struct LarkChat: Equatable {
    let chatID: String
    let threadID: String?

    init?(chatID: String, threadID: String? = nil) {
        guard Self.isID(chatID, prefix: "oc_"), threadID.map({ Self.isID($0, prefix: "omt_") }) ?? true else { return nil }
        self.chatID = chatID
        self.threadID = threadID
    }

    /// A scope part that is not a topic leaves the jump on the chat.
    init?(scope: String) {
        let parts = scope.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let topic = parts.dropFirst().first.flatMap { Self.isID($0, prefix: "omt_") ? $0 : nil }
        self.init(chatID: parts[0], threadID: topic)
    }

    /// Opens the topic, or the chat when the conversation has none. Feishu documents only
    /// `chat/open`; `thread/open` is the link Feishu's own clients register for opening a topic.
    var url: URL? {
        guard let threadID else { return URL(string: "lark://applink.feishu.cn/client/chat/open?openChatId=\(chatID)") }
        return URL(string: "lark://applink.feishu.cn/client/thread/open?open_chat_id=\(chatID)&open_thread_id=\(threadID)")
    }

    private static func isID(_ value: String, prefix: String) -> Bool {
        value.hasPrefix(prefix) && value.count > prefix.count
            && value.dropFirst(prefix.count).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
}
