import Foundation

/// Whether the user read a Feishu bridge result in Feishu itself. The bridge logs each message it
/// handles as one trace, naming the conversation it ran and the replies it sent; Feishu keeps a
/// bot message's read receipts for 7 days. A finished turn counts as read once the user is among
/// the readers of the bot's last reply to it. Feishu's read times are not used: for a reply that
/// arrives while its topic is open they can predate the reply itself.
///
/// Feishu answers only through the bot, so the check runs lark-cli with the bridge's own binding
/// for that bot (the bot's secret stays in lark-cli's keychain entry). Read-only, off the main
/// thread, and at most once a minute for each unread result.
final class LarkReadReceipts: @unchecked Sendable {
    static let live = LarkReadReceipts(home: LarkBridgeLookup.defaultHome)
    /// How long one unread result waits before it is checked again.
    static let recheckInterval: TimeInterval = 60
    /// Feishu answers read receipts only for messages sent in the last 7 days.
    static let receiptWindow: TimeInterval = 7 * 86_400
    /// A reply comes a moment after the turn finishes; allow for the two clocks' order.
    static let replySlack: TimeInterval = 60

    /// Open IDs of the users who read a bot message, or nil when Feishu did not answer.
    typealias Readers = (_ configDirectory: URL, _ messageID: String) -> Set<String>?

    private static let queue = DispatchQueue(label: "io.github.suiyun08.AgentTally.LarkReadReceipts", qos: .utility)

    private let home: URL
    private let readers: Readers
    private let schedule: (@escaping () -> Void) -> Void
    private let lock = NSLock()
    /// Conversation ID → finish time of its latest turn read in Feishu.
    private var readTurns: [String: Date] = [:]
    private var askedAt: [String: Date] = [:]

    init(
        home: URL,
        readers: @escaping Readers = LarkReadReceipts.larkCLIReaders,
        schedule: @escaping (@escaping () -> Void) -> Void = { LarkReadReceipts.queue.async(execute: $0) }
    ) {
        self.home = home
        self.readers = readers
        self.schedule = schedule
    }

    /// Conversation ID → finish time of the latest turn the user read in Feishu.
    func readTurnsSnapshot() -> [String: Date] {
        lock.lock()
        defer { lock.unlock() }
        return readTurns
    }

    /// Asks Feishu, in the background, whether the user read this unread bridge result.
    func request(_ session: SessionData, now: Date) {
        guard session.status == .done, let profile = session.larkChannelProfile,
              LarkBridgeLookup.isProfileName(profile) else { return }
        let conversationID = session.harnessSessionId ?? session.sessionId
        let finishedAt = session.statusChangedAt ?? session.lastActivity
        guard now.timeIntervalSince(finishedAt) < Self.receiptWindow else { return }

        lock.lock()
        let due = (readTurns[conversationID] ?? .distantPast) < finishedAt
            && now.timeIntervalSince(askedAt[conversationID] ?? .distantPast) >= Self.recheckInterval
        if due { askedAt[conversationID] = now }
        lock.unlock()
        guard due else { return }

        schedule { [self] in
            guard self.isRead(profile: profile, conversationID: conversationID, finishedAt: finishedAt) else { return }
            self.lock.lock()
            self.readTurns[conversationID] = max(self.readTurns[conversationID] ?? .distantPast, finishedAt)
            self.lock.unlock()
        }
    }

    private func isRead(profile: String, conversationID: String, finishedAt: Date) -> Bool {
        let profileDirectory = home.appendingPathComponent("profiles/\(profile)")
        let configDirectory = profileDirectory.appendingPathComponent("lark-cli/lark-channel")
        guard let user = Self.userOpenID(configDirectory: configDirectory),
              let reply = Self.lastReply(
                  conversationID: conversationID, finishedAt: finishedAt,
                  logsDirectory: profileDirectory.appendingPathComponent("logs")
              ),
              let readers = readers(configDirectory, reply) else { return false }
        return readers.contains(user)
    }

    // MARK: - Bridge files

    /// The user the bot answers, as lark-cli recorded them when the bridge bound the bot.
    static func userOpenID(configDirectory: URL) -> String? {
        guard let data = try? Data(contentsOf: configDirectory.appendingPathComponent("config.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let app = (root["apps"] as? [[String: Any]])?.first,
              let user = (app["users"] as? [[String: Any]])?.first,
              let openID = user["userOpenId"] as? String,
              isID(openID, prefix: "ou_") else { return nil }
        return openID
    }

    /// The bot's last reply in the trace that last ran the conversation, from the bridge's daily
    /// logs (`bridge-YYYYMMDD.jsonl`). A trace names its conversation in `session` events (`set`
    /// and `resume`; Codex's `set-thread`) and its replies in `outbound` `sent` events. Nil until
    /// that trace has replied after the turn finished.
    static func lastReply(conversationID: String, finishedAt: Date, logsDirectory: URL) -> String? {
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var conversationOfTrace: [String: (id: String, at: Date)] = [:]
        var lastSentOfTrace: [String: (id: String, at: Date)] = [:]
        for url in logFiles(in: logsDirectory, since: finishedAt) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n")
            where line.contains(#""phase":"session""#) || line.contains(#""phase":"outbound""#) {
                guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let trace = event["traceId"] as? String,
                      let at = (event["ts"] as? String).flatMap(dates.date(from:)) else { continue }
                switch (event["phase"] as? String, event["event"] as? String) {
                case ("session"?, "set"?), ("session"?, "resume"?), ("session"?, "set-thread"?):
                    // The last one wins: a resume that falls back to a new thread names it next.
                    if let id = (event["sessionId"] as? String) ?? (event["threadId"] as? String) {
                        conversationOfTrace[trace] = (id, at)
                    }
                case ("outbound"?, "sent"?):
                    if let id = event["messageId"] as? String, isID(id, prefix: "om_") {
                        lastSentOfTrace[trace] = (id, at)
                    }
                default:
                    break
                }
            }
        }
        guard let trace = conversationOfTrace.filter({ $0.value.id == conversationID })
                  .max(by: { $0.value.at < $1.value.at })?.key,
              let reply = lastSentOfTrace[trace],
              reply.at >= finishedAt.addingTimeInterval(-replySlack) else { return nil }
        return reply.id
    }

    /// Daily logs from the day before the turn finished onward, oldest first.
    private static func logFiles(in directory: URL, since date: Date) -> [URL] {
        let days = DateFormatter()
        days.locale = Locale(identifier: "en_US_POSIX")
        days.dateFormat = "yyyyMMdd"
        let first = "bridge-\(days.string(from: date.addingTimeInterval(-86_400))).jsonl"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { $0.hasPrefix("bridge-") && $0.hasSuffix(".jsonl") && $0 >= first }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    private static func isID(_ value: String, prefix: String) -> Bool {
        value.hasPrefix(prefix) && value.count > prefix.count
            && value.dropFirst(prefix.count).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    // MARK: - Feishu

    /// Who read a bot message, by open ID, asked through lark-cli as the bot.
    static func larkCLIReaders(configDirectory: URL, messageID: String) -> Set<String>? {
        var readers: Set<String> = []
        var pageToken: String?
        for _ in 0..<5 {
            var params: [String: Any] = ["user_id_type": "open_id", "page_size": 100]
            if let pageToken { params["page_token"] = pageToken }
            guard let paramsJSON = try? JSONSerialization.data(withJSONObject: params),
                  let output = runLarkCLI(
                      ["--as", "bot", "api", "GET", "/open-apis/im/v1/messages/\(messageID)/read_users",
                       "--params", String(decoding: paramsJSON, as: UTF8.self)],
                      configDirectory: configDirectory
                  ),
                  let root = try? JSONSerialization.jsonObject(with: output) as? [String: Any],
                  root["ok"] as? Bool == true,
                  let page = root["data"] as? [String: Any] else { return nil }
            for case let item as [String: Any] in page["items"] as? [Any] ?? [] {
                if let openID = item["user_id"] as? String { readers.insert(openID) }
            }
            guard page["has_more"] as? Bool == true,
                  let next = page["page_token"] as? String, !next.isEmpty else { return readers }
            pageToken = next
        }
        return readers
    }

    /// Runs lark-cli against one bot's config directory; its output on success.
    private static func runLarkCLI(_ arguments: [String], configDirectory: URL) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["lark-cli"] + arguments
        // An app's PATH has no Homebrew; lark-cli's launcher also needs node from there.
        process.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "LARKSUITE_CLI_CONFIG_DIR": configDirectory.path,
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 20, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return process.terminationStatus == 0 ? data : nil
    }
}
