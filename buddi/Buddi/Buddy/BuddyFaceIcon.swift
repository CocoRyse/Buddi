import Lottie
import SwiftUI

/// Closed-notch mini face. Task-aware: plays the buddy's Lottie art when the
/// species has it (scaled to the notch), otherwise renders the one-line ASCII
/// face driven by the shared animator.
struct BuddyFaceIcon: View {
    var fontSize: CGFloat = 10
    var animated: Bool = true

    @ObservedObject private var animator = BuddyManager.shared.animator

    private var identity: BuddyIdentity { BuddyManager.shared.effectiveIdentity }

    var body: some View {
        let task = animator.effectiveTask
        if BuddyArtLibrary.hasArt(for: identity.species),
           let animation = miniAnimation(for: task) {
            BuddyLottieView(animation: animation)
                .aspectRatio(BuddyArtLibrary.aspectRatio(of: animation), contentMode: .fit)
                .frame(height: fontSize * 2.2)
        } else {
            Text(SpriteFrameLogic.oneLineFace(for: task, species: identity.species, eye: identity.eye))
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .foregroundColor(faceColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// Task art when it exists, idle art otherwise (tasks without art producers).
    private func miniAnimation(for task: BuddyTask) -> LottieAnimation? {
        BuddyArtLibrary.lottieAnimation(for: identity.species, task: task)
            ?? BuddyArtLibrary.idleAnimation(for: identity.species)
    }

    private var faceColor: Color {
        if animator.effectiveTask == .error || animator.effectiveTask == .panic { return .red }
        return Color(nsColor: identity.rarity.nsColor)
    }
}
