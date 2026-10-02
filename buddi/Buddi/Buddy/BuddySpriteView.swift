import SwiftUI

/// Adaptive buddy sprite: plays the task's Lottie art when it exists
/// (capybara/ghost, artboards 400x300), otherwise falls back to the ASCII sprite.
struct BuddySpriteView: View {
    @ObservedObject var animator: SpriteAnimator
    let identity: BuddyIdentity
    var asciiFontSize: CGFloat = 12

    var body: some View {
        let task = animator.effectiveTask
        if let animation = BuddyArtLibrary.lottieAnimation(for: identity.species, task: task) {
            BuddyLottieView(animation: animation, speed: playbackSpeed(for: task))
                .aspectRatio(BuddyArtLibrary.aspectRatio(of: animation), contentMode: .fit)
        } else {
            ASCIIFullSpriteView(animator: animator, identity: identity, fontSize: asciiFontSize)
        }
    }

    /// Task moods play at slightly different tempos; sleeping is slowed for a
    /// dozing feel regardless of which art backs it.
    private func playbackSpeed(for task: BuddyTask) -> Double {
        switch task {
        case .working: 1.2
        case .panic: 1.6
        case .celebrate: 1.3
        case .sleeping: 0.6
        default: 1.0
        }
    }
}
