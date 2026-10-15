import AppKit
import SwiftUI

/// Draws an agent's small mark: its brand icon where cctop ships one, else its name. One
/// drawing serves the menu bar, the notch pill, the top bar, and the session cards.
enum AgentMark {
    static let claudeOrange = NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
    static let deepSeekBlue = NSColor(srgbRed: 0x4D / 255, green: 0x6B / 255, blue: 0xFE / 255, alpha: 1)

    private enum Shape {
        /// A brand-colored rounded tile with the glyph in white.
        case tile(String, NSColor)
        /// A full-color image as shipped.
        case image(String)
        /// A one-color glyph: a fixed brand color, or the ink passed in.
        case glyph(String, NSColor?)
        case text(String)
    }

    private static func shape(for badge: AgentBadge) -> Shape {
        switch badge {
        case .cc, .claudeDesktop: return .tile("AgentClaude", claudeOrange)
        case .codex: return .image("AgentCodex")
        case .dsh: return .glyph("AgentDeepSeek", deepSeekBlue)
        case .opencode: return .glyph("AgentOpenCode", nil)
        case .pi: return .text("\u{03C0}")
        case .other(let name): return .text(name)
        }
    }

    /// The asset a shape needs, or a text fallback when the asset is missing from the bundle.
    private static func resolved(_ badge: AgentBadge) -> Shape {
        let shape = shape(for: badge)
        switch shape {
        case .tile(let name, _), .image(let name), .glyph(let name, _):
            return NSImage(named: name) == nil ? .text(badge.label) : shape
        case .text:
            return shape
        }
    }

    private static func font(height: CGFloat) -> NSFont {
        .systemFont(ofSize: height * 0.86, weight: .semibold)
    }

    /// How wide the mark is at `height`: square for icons, the text's width for names.
    static func width(for badge: AgentBadge, height: CGFloat) -> CGFloat {
        guard case .text(let text) = resolved(badge) else { return height }
        return ceil(NSAttributedString(string: text, attributes: [.font: font(height: height)]).size().width)
    }

    /// Draws into the current graphics context. `ink` colors one-color marks and names.
    static func draw(_ badge: AgentBadge, in rect: NSRect, ink: NSColor) {
        switch resolved(badge) {
        case .tile(let name, let color):
            color.setFill()
            let radius = rect.height * 0.26
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            NSImage(named: name).map { tinted($0, .white).draw(in: rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)) }
        case .image(let name):
            NSImage(named: name)?.draw(in: rect)
        case .glyph(let name, let color):
            NSImage(named: name).map { tinted($0, color ?? ink).draw(in: rect) }
        case .text(let text):
            let string = NSAttributedString(string: text, attributes: [
                .font: font(height: rect.height), .foregroundColor: ink,
            ])
            let size = string.size()
            string.draw(at: NSPoint(x: rect.minX, y: rect.midY - size.height / 2))
        }
    }

    /// An image that redraws in whatever appearance it lands in, for SwiftUI.
    static func image(for badge: AgentBadge, height: CGFloat, ink: NSColor) -> NSImage {
        let size = NSSize(width: width(for: badge, height: height), height: height)
        return NSImage(size: size, flipped: false) { rect in
            draw(badge, in: rect, ink: ink)
            return true
        }
    }

    private static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// An agent's mark in SwiftUI, named in its tooltip and for VoiceOver.
struct AgentMarkView: View {
    let badge: AgentBadge
    var height: CGFloat = 11
    var ink: NSColor = .secondaryLabelColor

    var body: some View {
        Image(nsImage: AgentMark.image(for: badge, height: height, ink: ink))
            .help(badge.fullName)
            .accessibilityLabel(badge.fullName)
    }
}
