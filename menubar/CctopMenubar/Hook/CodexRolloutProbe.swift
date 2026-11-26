import Foundation

/// Reads the two facts the hook needs from a Codex rollout (the hook's `transcript_path`) without
/// parsing the whole file: who answers the thread's permission requests, and how it was started.
enum CodexRolloutProbe {
    /// Codex's own reviewer model answers permission requests; the user is never asked.
    static let autoReviewer = "auto_review"
    /// The thread started from `codex exec`.
    static let execSource = "exec"

    private static let chunkSize = 256 * 1024
    /// Settings are written at least once per turn, so a turn's worth of tail is enough.
    private static let maxTailScan: UInt64 = 16 * 1024 * 1024
    /// The first line (`session_meta`) carries the base instructions, so it can be long.
    private static let maxFirstLine = 4 * 1024 * 1024

    /// The approvals reviewer the thread applied last (`auto_review` or `user`), or nil when the
    /// rollout can't be read.
    static func approvalsReviewer(atPath path: String) -> String? {
        lastStringValue(forKey: "approvals_reviewer", atPath: path)
    }

    /// The `source` Codex recorded when the thread started: `exec`, `vscode` (Codex Desktop),
    /// `cli`, ... Subagent threads record an object there and read as nil.
    static func sessionSource(atPath path: String) -> String? {
        guard let line = firstLine(atPath: path),
              let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              row["type"] as? String == "session_meta",
              let payload = row["payload"] as? [String: Any] else { return nil }
        return payload["source"] as? String
    }

    /// The value of the last `"key":"value"` pair in the file, searched from the end. Codex writes
    /// compact JSON, so the pair has no spaces; a key that ends with `key` (such as
    /// `requested_approvals_reviewer`) doesn't match because of the leading quote.
    static func lastStringValue(forKey key: String, atPath path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard var upper = try? handle.seekToEnd() else { return nil }
        let marker = Data("\"\(key)\":\"".utf8)
        // The start of the later chunk, so a pair split across two chunks is still found whole.
        var carry = Data()
        var scanned: UInt64 = 0
        while upper > 0, scanned < maxTailScan {
            let lower = upper > UInt64(chunkSize) ? upper - UInt64(chunkSize) : 0
            guard (try? handle.seek(toOffset: lower)) != nil,
                  let chunk = try? handle.read(upToCount: Int(upper - lower)) else { return nil }
            let window = chunk + carry
            if let range = window.range(of: marker, options: .backwards) {
                guard let quote = window[range.upperBound...].firstIndex(of: UInt8(ascii: "\"")) else { return nil }
                return String(data: window[range.upperBound..<quote], encoding: .utf8)
            }
            carry = chunk.prefix(marker.count + 64)
            scanned += upper - lower
            upper = lower
        }
        return nil
    }

    private static func firstLine(atPath path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var line = Data()
        while line.count < maxFirstLine, let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let newline = chunk.firstIndex(of: 0x0A) {
                line.append(chunk[chunk.startIndex..<newline])
                return line
            }
            line.append(chunk)
        }
        return line.isEmpty ? nil : line
    }
}

extension HookEvent {
    /// Under automatic review, Codex runs PermissionRequest hooks before its reviewer model decides,
    /// so the request is the reviewer's to answer, not the user's. An unreadable rollout keeps the
    /// request as one for the user.
    func resolvingCodexReview(input: HookInput) -> HookEvent {
        guard self == .permissionRequest,
              input.resolvedHarnessName == SessionData.codexSource,
              let path = input.transcriptPath,
              CodexRolloutProbe.approvalsReviewer(atPath: path) == CodexRolloutProbe.autoReviewer
        else { return self }
        return .permissionAutoReviewed
    }
}

extension HookHandler {
    /// A Codex thread nobody is watching: an ephemeral thread with no rollout (Codex Desktop's
    /// suggestion, review and title helpers, `codex exec --ephemeral`) or a `codex exec` run (batch
    /// jobs, automations, agents' helpers). Feishu bridge conversations also run through
    /// `codex exec`, but someone is waiting on those. Decided on the prompt: by then every thread
    /// that keeps a rollout has one.
    static func isUnwatchedCodexThread(_ input: HookInput, _ larkChannelProfile: String?) -> Bool {
        guard input.resolvedHarnessName == SessionData.codexSource, larkChannelProfile == nil else { return false }
        if input.transcriptPathWasExplicitlyNull { return true }
        guard let path = input.transcriptPath else { return false }
        return CodexRolloutProbe.sessionSource(atPath: path) == CodexRolloutProbe.execSource
    }
}
