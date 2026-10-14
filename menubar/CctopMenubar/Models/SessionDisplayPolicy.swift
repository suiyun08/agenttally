import Foundation

/// Selects display buckets and reconciles canonical order on `UserSession` values.
/// It reads `displayRecord.data` only for lifecycle and status; identity stays on the group.
enum SessionDisplayPolicy {
    struct Signature: Equatable {
        let activeIDs: [SessionIdentityPolicy.LogicalIdentity]
        let idleIDs: [SessionIdentityPolicy.LogicalIdentity]

        static let empty = Signature(activeIDs: [], idleIDs: [])
    }


    static func activeSessions(from userSessions: [UserSession], now: Date = Date()) -> [UserSession] {
        userSessions.filter { isActive($0.displayRecord.data, now: now) }
    }

    static func idleSessions(from userSessions: [UserSession], now: Date = Date()) -> [UserSession] {
        userSessions.filter { isIdle($0.displayRecord.data, now: now) }
    }

    /// Keeps Active status groups in priority order while preserving the relative order of peers
    /// that remain in a group. Sessions entering a group append after its surviving members.
    /// Idle groups keep the existing lifecycle, status, and recency order at the manager boundary.
    static func reconcilingOrder(
        in userSessions: [UserSession],
        preserving previousUserSessions: [UserSession],
        now: Date = Date()
    ) -> [UserSession] {
        let active = activeSessions(from: userSessions, now: now)
        let activeByIdentity = Dictionary(
            active.map { ($0.identity, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeIdentities = Set(activeByIdentity.keys)
        var groups = Array(repeating: [UserSession](), count: SessionStatus.idle.sortOrder + 1)
        var placedIdentities: Set<SessionIdentityPolicy.LogicalIdentity> = []

        for previous in activeSessions(from: previousUserSessions, now: now) {
            guard let current = matchingCurrentUserSession(
                for: previous,
                active: active,
                activeByIdentity: activeByIdentity
            ),
                  !placedIdentities.contains(current.identity),
                  current.status.sortOrder == previous.status.sortOrder else { continue }
            groups[current.status.sortOrder].append(current)
            placedIdentities.insert(current.identity)
        }

        for current in active {
            guard placedIdentities.insert(current.identity).inserted else { continue }
            groups[current.status.sortOrder].append(current)
        }

        let orderedActive = groups.flatMap { $0 }
        let orderedIdle = userSessions
            .filter { !activeIdentities.contains($0.identity) }
            .sorted(by: precedesInIdleOrder)
        return orderedActive + orderedIdle
    }

    static func signature(for userSessions: [UserSession], now: Date = Date()) -> Signature {
        Signature(
            activeIDs: activeSessions(from: userSessions, now: now).map(\.identity),
            idleIDs: idleSessions(from: userSessions, now: now).map(\.identity)
        )
    }

    private static func matchingCurrentUserSession(
        for previous: UserSession,
        active: [UserSession],
        activeByIdentity: [SessionIdentityPolicy.LogicalIdentity: UserSession]
    ) -> UserSession? {
        if let exact = activeByIdentity[previous.identity] { return exact }
        guard case .legacy(let stableKey) = previous.identity else { return nil }
        let matches = active.filter { userSession in
            userSession.records.contains {
                SessionIdentityPolicy.stableKey(for: $0.data) == stableKey
            }
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func precedesInIdleOrder(_ left: UserSession, _ right: UserSession) -> Bool {
        let leftData = left.displayRecord.data
        let rightData = right.displayRecord.data
        return (leftData.lifecycle.rawValue, left.status.sortOrder, rightData.lastActivity)
            < (rightData.lifecycle.rawValue, right.status.sortOrder, leftData.lastActivity)
    }

    /// Active means "worth a look now": running, waiting on the user, or a finished turn the
    /// user has not seen. A connected session with nothing to do is Idle; a disconnected
    /// (dormant) one belongs to Recent.
    static func needsLook(_ session: SessionData) -> Bool {
        switch session.status {
        case .working, .compacting, .background, .waitingPermission, .waitingInput, .needsAttention:
            return true
        case .done:
            return session.isUnseenDone
        case .idle:
            return false
        }
    }

    private static func isIdle(_ session: SessionData, now: Date) -> Bool {
        session.lifecycle == .active && !needsLook(session)
    }

    private static func isActive(_ session: SessionData, now: Date) -> Bool {
        session.lifecycle == .active && needsLook(session)
    }

    static func dormantSessions(from userSessions: [UserSession]) -> [UserSession] {
        userSessions.filter { $0.displayRecord.data.lifecycle == .dormant }
    }

}
