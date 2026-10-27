import Foundation

/// One `SessionData` value plus the file and runtime evidence for that value.
/// This in-memory record is not part of the persisted JSON schema.
/// `mtime` is `.distantPast` when unknown so lifecycle preference remains a total order.
struct SessionRecord: Equatable {
    let data: SessionData
    let lifecycleRank: Int   // 0 = active, 1 = dormant, 2 = finished (lower = preferred)
    let mtime: Date
    let path: String         // absolute file path; final, total tiebreak

    func replacingData(_ data: SessionData) -> SessionRecord {
        SessionRecord(data: data, lifecycleRank: lifecycleRank, mtime: mtime, path: path)
    }
}

/// Tunable windows for lifecycle derivation.
struct LifecycleWindows {
    let active: TimeInterval     // fallback "recent activity counts as active" threshold
    let retention: TimeInterval  // dormant desktop -> finished age-out from disconnected_at
}

enum SessionConnectionState: Equatable {
    case connected
    case disconnected
}

enum SessionLifecyclePolicy {
    /// Pure connection derivation. Codex uses one source-level policy across every surface;
    /// other sessions retain their existing host-specific connection evidence. A Feishu bridge
    /// conversation, whose process ends after every message, stays connected for a while after
    /// its last activity, and for as long as `bridgeKeepsLive` says its bot holds it with
    /// something for the user.
    static func connectionState(
        for session: SessionData, hostClass: SessionHostClass, processAlive: Bool,
        now: Date, windows: LifecycleWindows, desktopAppRunning: Bool? = nil, bridgeKeepsLive: Bool = false
    ) -> SessionConnectionState {
        if session.endedAt != nil { return .disconnected }
        if session.larkChannelProfile != nil {
            let recentlyActive = now.timeIntervalSince(session.lastActivity) < windows.active
            return processAlive || recentlyActive || bridgeKeepsLive ? .connected : .disconnected
        }
        if session.isCodex {
            let recentlyActive = now.timeIntervalSince(session.lastActivity) < windows.active
            return processAlive || recentlyActive ? .connected : .disconnected
        }
        if hostClass == .desktop, let desktopAppRunning {
            return desktopAppRunning ? .connected : .disconnected
        }
        return processAlive ? .connected : .disconnected
    }

    /// Pure lifecycle derivation. Connection is detected uniformly first; host policy then
    /// decides what disconnected means for desktop versus non-desktop sessions.
    static func lifecycle(
        for session: SessionData, hostClass: SessionHostClass, processAlive: Bool,
        now: Date, windows: LifecycleWindows, desktopAppRunning: Bool? = nil, bridgeKeepsLive: Bool = false
    ) -> SessionLifecycle {
        // Codex has one absolute inactivity cap across every surface. Bundle, PID,
        // desktop-app, and app-server evidence cannot keep a 14-day-old record alive.
        if session.isCodex, now.timeIntervalSince(session.lastActivity) >= windows.retention {
            return .finished
        }
        // Absolute idle age-cap for non-Codex desktop sessions (issue #155): past the retention
        // window a session is finished outright, even while its app keeps running.
        // Without this, retirement depends on disconnectedAt — which is only stamped
        // once the session goes dormant, impossible while the app stays open.
        if hostClass == .desktop, now.timeIntervalSince(session.lastActivity) > windows.retention {
            return .finished
        }
        let connection = connectionState(
            for: session,
            hostClass: hostClass,
            processAlive: processAlive,
            now: now,
            windows: windows,
            desktopAppRunning: desktopAppRunning,
            bridgeKeepsLive: bridgeKeepsLive
        )
        if connection == .connected { return .active }
        if session.isCodex { return .dormant }
        guard hostClass == .desktop else { return .finished }
        guard let disconnectedAt = session.disconnectedAt else { return .dormant }
        return now.timeIntervalSince(disconnectedAt) <= windows.retention ? .dormant : .finished
    }

    static func prefers(_ lhs: SessionRecord, over rhs: SessionRecord) -> Bool {
        if lhs.lifecycleRank != rhs.lifecycleRank { return lhs.lifecycleRank < rhs.lifecycleRank }
        if lhs.data.lastActivity != rhs.data.lastActivity {
            return lhs.data.lastActivity > rhs.data.lastActivity
        }
        if lhs.data.effectiveEndDate != rhs.data.effectiveEndDate {
            return lhs.data.effectiveEndDate > rhs.data.effectiveEndDate
        }
        if lhs.mtime != rhs.mtime { return lhs.mtime > rhs.mtime }
        return lhs.path < rhs.path
    }
}
