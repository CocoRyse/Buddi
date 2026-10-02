import SwiftUI

/// Multi-line animated sprite view for the expanded panel.
/// Uses TimelineView for smooth frame cycling.
struct ASCIIFullSpriteView: View {
    @ObservedObject var animator: SpriteAnimator
    let identity: BuddyIdentity
    var fontSize: CGFloat = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.8, paused: false)) { timeline in
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / 0.8)
            let lines = spriteLines(tick: tick)

            VStack(alignment: .center, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundColor(textColor)
                }
            }
        }
    }

    private func spriteLines(tick: Int) -> [String] {
        let eye: BuddyEye
        switch animator.effectiveTask {
        case .error: eye = .cross
        case .sleeping: eye = .dot
        default: eye = identity.eye
        }

        return SpriteData.renderFrame(
            species: identity.species,
            eye: eye,
            hat: identity.hat,
            frame: tick
        )
    }

    private var textColor: Color {
        if animator.effectiveTask == .error { return .red }
        return Color(nsColor: identity.rarity.nsColor)
    }
}
