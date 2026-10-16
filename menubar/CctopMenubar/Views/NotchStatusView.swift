import SwiftUI

struct NotchStatusView: View {
    let counts: StatusCounts
    var themeId: String = ""

    static let leadingPadding: CGFloat = 5
    static let trailingPadding: CGFloat = 2
    private static let emptyLineWidth: CGFloat = 14

    /// Width of the dots (or the empty line) for a pill whose content may not exceed `maxWidth`.
    static func contentWidth(for counts: StatusCounts, maxWidth: CGFloat) -> CGFloat {
        guard !counts.dotGroups.isEmpty else { return emptyLineWidth }
        return StatusDotLayout(groups: counts.dotGroups, metrics: .notch, maxWidth: maxWidth).width
    }

    var body: some View {
        Group {
            if counts.dotGroups.isEmpty {
                Capsule().fill(Color.white.opacity(0.52))
                    .frame(width: Self.emptyLineWidth, height: 3)
            } else {
                StatusDotsView(
                    layout: StatusDotLayout(
                        groups: counts.dotGroups,
                        metrics: .notch,
                        maxWidth: NotchStatusController.maxContentWidth
                    ),
                    metrics: .notch,
                    palette: .notch
                )
            }
        }
        .frame(height: 11)
        .id(themeId)
        .padding(.leading, Self.leadingPadding)
        .padding(.trailing, Self.trailingPadding)
        .padding(.top, 4)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.90))
        .clipShape(NotchTabShape(radius: 6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(counts.accessibilityLabel)
    }
}

/// Notch tab shape: flat top and right edge (meets the notch), rounded bottom-left corner only.
private struct NotchTabShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius),
            radius: radius
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Mixed") {
    NotchStatusView(counts: StatusCounts(permission: 1, attention: 1, working: 2, idle: 1))
        .padding()
        .background(Color.black)
}

#Preview("Needs permission") {
    NotchStatusView(counts: StatusCounts(permission: 2, attention: 0, working: 1, idle: 0))
        .padding()
        .background(Color.black)
}

#Preview("All working") {
    NotchStatusView(counts: StatusCounts(permission: 0, attention: 0, working: 4, idle: 0))
        .padding()
        .background(Color.black)
}

#Preview("All idle") {
    NotchStatusView(counts: StatusCounts(permission: 0, attention: 0, working: 0, idle: 3))
        .padding()
        .background(Color.black)
}

#Preview("1 attention in 10 (min width)") {
    NotchStatusView(counts: StatusCounts(permission: 0, attention: 1, working: 7, idle: 2))
        .padding()
        .background(Color.black)
}

#Preview("1 permission in 20 (extreme squeeze)") {
    NotchStatusView(counts: StatusCounts(permission: 1, attention: 0, working: 19, idle: 0))
        .padding()
        .background(Color.black)
}

#Preview("No sessions") {
    NotchStatusView(counts: StatusCounts(permission: 0, attention: 0, working: 0, idle: 0))
        .padding()
        .background(Color.black)
}
