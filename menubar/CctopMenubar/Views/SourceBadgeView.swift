import SwiftUI

/// Renders a session's source/host as its small agent mark, kept quiet so project names and
/// session state remain primary. Agents without a mark show their name.
struct SourceBadgeView: View {
    let badge: AgentBadge

    var body: some View {
        AgentMarkView(badge: badge, height: 11)
    }
}

#Preview("CC") {
    SourceBadgeView(badge: .cc).padding()
}
#Preview("Claude Desktop") {
    SourceBadgeView(badge: .claudeDesktop).padding()
}
#Preview("Codex") {
    SourceBadgeView(badge: .codex).padding()
}
#Preview("Opencode") {
    SourceBadgeView(badge: .opencode).padding()
}
#Preview("Pi") {
    SourceBadgeView(badge: .pi).padding()
}
#Preview("DSH") {
    SourceBadgeView(badge: .dsh).padding()
}
#Preview("All variants") {
    VStack(alignment: .leading, spacing: 12) {
        SourceBadgeView(badge: .cc)
        SourceBadgeView(badge: .claudeDesktop)
        SourceBadgeView(badge: .codex)
        SourceBadgeView(badge: .opencode)
        SourceBadgeView(badge: .pi)
    }
    .padding()
}
