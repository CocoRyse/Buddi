import Lottie
import SwiftUI

/// SwiftUI content hosted inside the PetRoamer window. Re-renders at the
/// roamer's tick rate (30 fps) because PetRoamer republishes its model each tick.
struct PetRoamerView: View {
    @ObservedObject var roamer: PetRoamer

    /// Drawn sprite size in points.
    static let spriteSize: CGFloat = 64

    private var identity: BuddyIdentity {
        BuddyManager.shared.effectiveIdentity
    }

    var body: some View {
        GeometryReader { _ in
            Group {
                if BuddyArtLibrary.hasArt(for: identity.species),
                   let animation = currentAnimation {
                    BuddyLottieView(animation: animation.animation, speed: animation.speed)
                        .aspectRatio(BuddyArtLibrary.aspectRatio(of: animation.animation), contentMode: .fit)
                } else {
                    asciiFace
                }
            }
            .frame(width: Self.spriteSize, height: Self.spriteSize)
            .scaleEffect(x: roamer.model.direction, y: 1)
            .offset(
                x: roamer.model.x,
                y: bobOffset
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Art

    private var currentAnimation: (animation: LottieAnimation, speed: Double)? {
        let species = identity.species
        switch roamer.model.state {
        case .walk:
            guard let animation = BuddyArtLibrary.walkAnimation(for: species) else {
                return nil
            }
            return (animation, 1)
        case .idle:
            guard let animation = BuddyArtLibrary.idleAnimation(for: species) else {
                return nil
            }
            return (animation, 1)
        case .nap:
            guard let animation = BuddyArtLibrary.napAnimation(for: species) else {
                return nil
            }
            return (animation, 0.5)
        }
    }

    // MARK: - ASCII Fallback

    private var asciiFace: some View {
        let task: BuddyTask = roamer.model.state == .nap ? .sleeping : .idle
        return Text(SpriteFrameLogic.oneLineFace(for: task, species: identity.species, eye: identity.eye))
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(Color(nsColor: identity.rarity.nsColor))
            .lineLimit(1)
            .fixedSize()
    }

    /// Gentle vertical bob while walking (view re-renders at 30 fps).
    private var bobOffset: CGFloat {
        guard roamer.model.state == .walk else { return 0 }
        let phase = Date().timeIntervalSinceReferenceDate * 2 * .pi / 1.2
        return CGFloat(sin(phase) * 2)
    }
}
