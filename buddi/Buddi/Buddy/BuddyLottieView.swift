import Lottie
import SwiftUI

/// SwiftUI host for a Lottie animation on macOS. Restarts playback from the
/// beginning whenever a different `LottieAnimation` object is supplied, so
/// swapping task art (idle → panic → …) restarts cleanly.
struct BuddyLottieView: NSViewRepresentable {
    let animation: LottieAnimation
    var speed: Double = 1.0
    var loopMode: LottieLoopMode = .loop

    final class Coordinator {
        /// Object identity of the currently installed animation.
        var currentAnimation: LottieAnimation?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.animationSpeed = CGFloat(speed)
        view.loopMode = loopMode
        view.shouldRasterizeWhenIdle = true
        view.play()
        context.coordinator.currentAnimation = animation
        return view
    }

    func updateNSView(_ nsView: LottieAnimationView, context: Context) {
        if context.coordinator.currentAnimation !== animation {
            context.coordinator.currentAnimation = animation
            nsView.animation = animation
            nsView.animationSpeed = CGFloat(speed)
            nsView.loopMode = loopMode
            nsView.play(fromProgress: 0, toProgress: 1, loopMode: loopMode)
        } else {
            nsView.animationSpeed = CGFloat(speed)
            nsView.loopMode = loopMode
            if !nsView.isAnimationPlaying {
                nsView.play()
            }
        }
    }
}
