import Combine
import Foundation

/// Watches plan quota utilization and drives buddy reactions:
/// - A persistent mood via `animator.quotaTask`: `.panic` above 80% utilization,
///   `.nervous` above 60%, otherwise cleared.
/// - A one-shot `.celebrate` flash when a quota window resets (seed-then-diff,
///   same pattern as BuddiSessionBridge's waiting-for-input detection: the first
///   seen value seeds the baseline without reacting).
@MainActor
final class QuotaReactionService: ObservableObject {
    static let shared = QuotaReactionService()

    private var cancellables = Set<AnyCancellable>()
    private var knownResetsAt: [String: Date] = [:]  // "fiveHour" / "sevenDay"

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }

        UsageService.shared.$usage
            .removeDuplicates()
            .sink { [weak self] usage in
                self?.react(to: usage)
            }
            .store(in: &cancellables)
    }

    private func react(to usage: UsageData) {
        applyQuotaMood(usage)
        detectResetAndCelebrate(usage)
    }

    // MARK: - Persistent Mood

    private func applyQuotaMood(_ usage: UsageData) {
        let level = usage.fiveHour ?? usage.sevenDay
        let animator = BuddyManager.shared.animator

        guard let utilization = level?.utilization else {
            animator.quotaTask = nil
            return
        }

        if utilization > 80 {
            animator.quotaTask = .panic
        } else if utilization > 60 {
            animator.quotaTask = .nervous
        } else {
            animator.quotaTask = nil
        }
    }

    // MARK: - Reset Celebration (seed-then-diff)

    private func detectResetAndCelebrate(_ usage: UsageData) {
        let windows: [String: QuotaPeriod?] = [
            "fiveHour": usage.fiveHour,
            "sevenDay": usage.sevenDay,
        ]

        var didReset = false
        let now = Date()

        for (key, period) in windows {
            // A window that disappeared loses its baseline; re-seed when it returns.
            guard let newResetsAt = period?.resetsAt else {
                knownResetsAt[key] = nil
                continue
            }

            // First sighting seeds the baseline without celebrating.
            guard let oldResetsAt = knownResetsAt[key] else {
                knownResetsAt[key] = newResetsAt
                continue
            }

            knownResetsAt[key] = newResetsAt

            guard newResetsAt != oldResetsAt else { continue }

            // The window rolled over: the deadline moved later, or the old one
            // already passed while the new one is still in the future.
            if newResetsAt > oldResetsAt || (oldResetsAt <= now && newResetsAt > now) {
                didReset = true
            }
        }

        if didReset {
            BuddyManager.shared.animator.flash(.celebrate, ticks: 8)
        }
    }
}
