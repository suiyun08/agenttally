import Foundation

/// The app's user-facing name: AgentTally, or 代理指示 in Simplified Chinese. Internal names keep
/// cctop (the hook binary, ~/.cctop, the cctop:// scheme) so running agent sessions stay connected.
enum AppBrand {
    static var name: String { String(localized: "AgentTally") }
}
