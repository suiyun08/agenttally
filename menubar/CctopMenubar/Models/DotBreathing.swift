import AppKit

/// The slow breathing of the dots that wait on the user: each one eases between hollow and
/// solid, keeping its color. Neighbouring dots start at different points, so they never pulse
/// together, and the rhythm is slow enough to read as a reminder rather than an alarm.
enum DotBreathing {
    /// One full breath, hollow to solid and back.
    static let period: TimeInterval = 3

    /// How filled a breathing dot is at `time`: 0 hollow, 1 solid. A cosine eases in and out at
    /// both ends. `time` is absolute, so a dot redrawn mid-breath carries on where it was.
    static func fill(at time: TimeInterval, phase: Double) -> Double {
        0.5 - 0.5 * cos(2 * .pi * (time / period + phase))
    }

    /// Where in the breath a dot starts, by its place in the menu bar: each dot a golden-ratio
    /// step on from the one before it, and each group half a breath from the group before, so
    /// neighbours never line up. A place keeps its phase, so a refresh never makes a dot jump.
    static func phase(groupIndex: Int, dotIndex: Int) -> Double {
        (Double(groupIndex) * 0.5 + Double(dotIndex) * 0.618).truncatingRemainder(dividingBy: 1)
    }
}

extension StatusDotGroup.Dot {
    /// Dots waiting on the user breathe — a permission request, a question, an unread result.
    /// Running work holds still.
    var breathes: Bool { self != .working }
}

extension StatusDotLayout {
    struct DotSpot: Equatable {
        let dot: StatusDotGroup.Dot
        let xPos: CGFloat
        let phase: Double
    }

    /// Every visible dot with its breathing phase, in layout order.
    var dotSpots: [DotSpot] {
        var spots: [DotSpot] = []
        var groupIndex = -1
        var dotIndex = 0
        for item in items {
            switch item {
            case .mark:
                groupIndex += 1
                dotIndex = 0
            case .dot(let dot, let xPos):
                let phase = DotBreathing.phase(groupIndex: max(groupIndex, 0), dotIndex: dotIndex)
                spots.append(DotSpot(dot: dot, xPos: xPos, phase: phase))
                dotIndex += 1
            case .overflow:
                break
            }
        }
        return spots
    }
}
