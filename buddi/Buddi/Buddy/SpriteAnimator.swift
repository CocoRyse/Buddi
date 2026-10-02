import Combine
import Foundation

/// Pure logic class that computes animation frame strings.
/// Owns the timer. Testable without any UI dependency.
///
/// Usage:
///   let animator = SpriteAnimator(identity: identity)
///   animator.task = .working  // timer resets, frames change
///   animator.$frameString    // observe the current rendered string
@MainActor
final class SpriteAnimator: ObservableObject {
    @Published private(set) var frameString: String = ""
    @Published private(set) var oneLine: String = ""

    /// Base task driven by session phase. Overridden by `quotaTask` (persistent quota mood)
    /// and transient `flash` reactions. Render priority: flash > quotaTask > task.
    var task: BuddyTask = .idle {
        didSet {
            guard task != oldValue else { return }
            // While a flash is showing, keep the new base for when the flash ends.
            recomputeEffective()
        }
    }

    /// Persistent mood driven by plan quota (e.g. `.panic` while utilization > 80%).
    /// Cleared by setting back to nil. Sits between the base task and flashes.
    var quotaTask: BuddyTask? {
        didSet {
            guard quotaTask != oldValue else { return }
            recomputeEffective()
        }
    }

    /// Show a transient reaction (e.g. `.error`) for a few ticks, then revert to
    /// `quotaTask ?? task`.
    func flash(_ reaction: BuddyTask, ticks: Int = 5) {
        flashTask = reaction
        flashCountdown = ticks
        applyEffective(reaction)
    }

    var identity: BuddyIdentity {
        didSet {
            guard identity != oldValue else { return }
            updateFrame()
        }
    }
    /// The task actually being rendered (base task, quota mood, or an active flash reaction).
    /// Views should read this (not `task`) so transient flashes and quota moods are visible.
    @Published private(set) var effectiveTask: BuddyTask = .idle
    private var tick: Int = 0
    private var timer: Timer?
    private var flashCountdown: Int = 0
    private var flashTask: BuddyTask?

    private func recomputeEffective() {
        applyEffective((flashCountdown > 0 ? flashTask : nil) ?? quotaTask ?? task)
    }

    private func applyEffective(_ newTask: BuddyTask) {
        guard newTask != effectiveTask else { return }
        effectiveTask = newTask
        tick = 0
        updateFrame()
        restartTimer()
    }

    init(identity: BuddyIdentity) {
        self.identity = identity
        updateFrame()
        restartTimer()
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Timer

    private func restartTimer() {
        timer?.invalidate()
        let interval = intervalForTask(effectiveTask)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.onTick()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func onTick() {
        tick += 1

        if flashCountdown > 0 {
            flashCountdown -= 1
            if flashCountdown == 0 {
                flashTask = nil
                applyEffective(quotaTask ?? task)  // flash ended — revert past the quota mood
                return
            }
        }

        updateFrame()
    }

    private func updateFrame() {
        frameString = SpriteFrameLogic.frame(
            for: effectiveTask,
            tick: tick,
            species: identity.species,
            eye: identity.eye
        )
        oneLine = SpriteFrameLogic.oneLineFace(
            for: effectiveTask,
            species: identity.species,
            eye: identity.eye
        )
    }

    private func intervalForTask(_ task: BuddyTask) -> TimeInterval {
        switch task {
        case .idle: 0.5       // 500ms tick
        case .working: 0.4    // 400ms cursor toggle
        case .reading: 0.8    // 800ms eye shift
        case .waiting: 0.5    // 500ms dot animation
        case .compacting: 0.4 // 400ms tilde
        case .sleeping: 1.2   // 1.2s zzz scroll
        case .error: 0.5      // 500ms
        case .success: 0.5    // 500ms countdown
        case .panic: 0.3      // 300ms frantic shake
        case .nervous: 0.45   // 450ms fidget
        case .celebrate: 0.25 // 250ms party
        }
    }
}

// MARK: - Pure Frame Logic (nonisolated, testable)

enum SpriteFrameLogic {
    static let idleSequence: [Int] = [0, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0, 2, 0, 0, 0]

    static func frame(
        for task: BuddyTask,
        tick: Int,
        species: BuddySpecies,
        eye: BuddyEye
    ) -> String {
        let baseFace = SpriteData.face(species: species, eye: eye)

        switch task {
        case .idle:
            let seq = idleSequence
            let index = tick % seq.count
            let value = seq[index]
            if value == -1 {
                return blinkFace(baseFace, eye: eye)
            }
            return baseFace

        case .working:
            let cursor = tick % 2 == 0 ? "|" : ""
            return baseFace + cursor

        case .reading:
            let phase = tick % 3
            if phase == 1 {
                return shiftEyeRight(baseFace, eye: eye)
            }
            return baseFace

        case .waiting:
            let dots = String(repeating: ".", count: (tick % 3) + 1)
            return baseFace + dots

        case .compacting:
            let suffix = tick % 2 == 0 ? "~" : "~~"
            return baseFace + suffix

        case .sleeping:
            let zCount = (tick % 3) + 1
            let zzz = String(repeating: "z", count: zCount)
            return sleepFace(baseFace, eye: eye) + " " + zzz

        case .error:
            return errorFace(baseFace, eye: eye)

        case .success:
            return baseFace + " \u{2713}"

        case .panic:
            // Wide-eyed alarm with frantic side jitter.
            let jitter = tick % 2 == 0 ? "\\" : "/"
            return errorFace(baseFace, eye: eye) + jitter + jitter

        case .nervous:
            // Glancing sideways, small dots of doubt.
            let phase = tick % 3
            if phase == 1 {
                return shiftEyeRight(baseFace, eye: eye) + ".."
            }
            return baseFace + ".."

        case .celebrate:
            // Sparkle rotation around the happy face.
            let sparkles = ["*", "+", "✦", "+"]
            return baseFace + " " + sparkles[tick % sparkles.count]
        }
    }

    static func oneLineFace(for task: BuddyTask, species: BuddySpecies, eye: BuddyEye) -> String {
        let base = SpriteData.face(species: species, eye: eye)
        let suffix = task.faceSuffix
        if task == .sleeping {
            return sleepFace(base, eye: eye) + suffix
        }
        if task == .error {
            return errorFace(base, eye: eye) + suffix
        }
        return base + suffix
    }

    static func blinkFace(_ face: String, eye: BuddyEye) -> String {
        face.replacingOccurrences(of: eye.rawValue, with: "-")
    }

    static func sleepFace(_ face: String, eye: BuddyEye) -> String {
        face.replacingOccurrences(of: eye.rawValue, with: "-")
    }

    static func errorFace(_ face: String, eye: BuddyEye) -> String {
        face.replacingOccurrences(of: eye.rawValue, with: "X")
    }

    static func shiftEyeRight(_ face: String, eye: BuddyEye) -> String {
        guard let range = face.range(of: eye.rawValue) else { return face }
        var result = face
        result.replaceSubrange(range, with: " ")
        return result
    }
}
