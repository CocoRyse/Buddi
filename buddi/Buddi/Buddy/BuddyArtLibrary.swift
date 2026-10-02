import Foundation
import Lottie

/// Loads and caches the Lottie sprite art shipped in Resources/BuddyArt/
/// (`<species>-<task>.json`, 400x300 artboards). Species without vector art
/// keep rendering their ASCII sprite; callers fall back when a lookup misses.
enum BuddyArtLibrary {
    private static let cache = NSCache<NSString, LottieAnimation>()

    /// Species that ship Lottie art today.
    private static func supportsArt(_ species: BuddySpecies) -> Bool {
        species == .capybara || species == .ghost
    }

    /// Task → art file key. nil = no art for this state (caller falls back or maps to idle).
    static func animationName(species: BuddySpecies, task: BuddyTask) -> String? {
        guard supportsArt(species) else { return nil }
        switch task {
        case .idle, .working, .waiting, .compacting, .error, .panic, .nervous, .celebrate:
            return "\(species.rawValue)-\(task.rawValue)"
        case .sleeping:
            // Capybara has dedicated sleep art; ghost has none, so it reuses
            // its idle animation (callers slow it down to fake dozing).
            return species == .capybara ? "\(species.rawValue)-sleep" : "\(species.rawValue)-idle"
        default:
            return nil // .reading/.success have no producers, no art
        }
    }

    static func lottieAnimation(for species: BuddySpecies, task: BuddyTask) -> LottieAnimation? {
        guard let name = animationName(species: species, task: task) else { return nil }
        // Personal overrides (downloaded art, gitignored) win over bundled art.
        if let external = lottieAnimation(named: "external-" + name) {
            return external
        }
        return lottieAnimation(named: name)
    }

    static func idleAnimation(for species: BuddySpecies) -> LottieAnimation? {
        lottieAnimation(for: species, task: .idle)
    }

    static func napAnimation(for species: BuddySpecies) -> LottieAnimation? {
        lottieAnimation(for: species, task: .sleeping)
    }

    /// Artboard aspect (w/h) of a loaded animation; falls back to the
    /// bundled 400x300 artboard ratio.
    static func aspectRatio(of animation: LottieAnimation) -> CGFloat {
        guard animation.size.height > 0 else { return 4.0 / 3.0 }
        return animation.size.width / animation.size.height
    }

    /// Loads an animation by file name (without extension), caching by name.
    /// Returns nil when the art is missing so callers can fall back to ASCII.
    static func lottieAnimation(named name: String) -> LottieAnimation? {
        if let cached = cache.object(forKey: name as NSString) { return cached }

        if let animation = LottieAnimation.named(name, bundle: .main, subdirectory: "BuddyArt") {
            cache.setObject(animation, forKey: name as NSString)
            return animation
        }

        // Fallback: resolve the JSON bytes ourselves (covers bundle layouts the
        // Lottie loader cannot enumerate), then decode.
        let candidates = [
            Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "BuddyArt"),
            Bundle.main.url(forResource: name, withExtension: "json"),
        ]
        for url in candidates.compactMap({ $0 }) {
            guard let data = try? Data(contentsOf: url),
                  let animation = try? LottieAnimation.from(data: data)
            else { continue }
            cache.setObject(animation, forKey: name as NSString)
            return animation
        }
        return nil
    }

    static func hasArt(for species: BuddySpecies) -> Bool {
        supportsArt(species)
    }

    static func walkAnimation(for species: BuddySpecies) -> LottieAnimation? {
        guard supportsArt(species) else { return nil }
        if let external = lottieAnimation(named: "external-\(species.rawValue)-walk") {
            return external
        }
        return lottieAnimation(named: "\(species.rawValue)-walk")
    }
}
