import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - Model

/// Pure state for the roaming menu-bar pet. Mutated by `PetRoamer` on a timer;
/// published so the hosted SwiftUI view re-renders at the tick rate.
struct PetRoamerModel: Equatable {
    enum State: Equatable {
        case walk
        case idle
        case nap
    }

    /// Horizontal position of the sprite's leading edge, in window coordinates.
    var x: CGFloat = 40
    /// 1 = facing right, -1 = facing left.
    var direction: CGFloat = 1
    var state: State = .walk
    /// When the current state ends (durations are randomized on state entry).
    var stateUntil = Date().addingTimeInterval(6)
    /// Walk speed in px/s, randomized on each walk entry (25-40).
    var speed: CGFloat = 32

    /// Advances the walk/idle/nap state machine by `dt` seconds.
    /// `bounds` is the walkable x-range (leading edge position).
    mutating func tick(dt: TimeInterval, bounds: CGRect) {
        let minX = bounds.minX
        let maxX = bounds.maxX
        guard minX < maxX else { return }

        if state == .walk {
            x += CGFloat(dt) * speed * direction
            if x <= minX {
                x = minX
                direction = 1
            } else if x >= maxX {
                x = maxX
                direction = -1
            }
        }

        let now = Date()
        guard now >= stateUntil else { return }

        switch state {
        case .walk:
            state = .idle
            stateUntil = now.addingTimeInterval(TimeInterval.random(in: 2...6))
        case .idle:
            if Double.random(in: 0...1) < 0.1 {
                state = .nap
                stateUntil = now.addingTimeInterval(TimeInterval.random(in: 8...15))
            } else {
                enterWalk(now: now)
            }
        case .nap:
            enterWalk(now: now)
        }
    }

    private mutating func enterWalk(now: Date) {
        state = .walk
        speed = CGFloat.random(in: 25...40)
        stateUntil = now.addingTimeInterval(TimeInterval.random(in: 4...10))
    }
}

// MARK: - Controller

/// Owns a borderless overlay window spanning the menu-bar band of the main
/// screen and animates a small pet walking back and forth across it.
/// The window sits at `.statusBar` level so the notch window (`.mainMenu + 3`)
/// naturally covers it — no special notch handling needed.
@MainActor
final class PetRoamer: ObservableObject {
    static let shared = PetRoamer()

    /// Reassigned every timer tick so SwiftUI re-renders at the tick rate.
    @Published private(set) var model = PetRoamerModel()

    private var window: NSWindow?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?

    private var isEnabled = false

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }

        Defaults.publisher(.roamingPetEnabled, options: [.initial])
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                self?.setRoaming(change.newValue)
            }
            .store(in: &cancellables)

        // Species/eye swaps: the view reads BuddyManager directly; nudge a
        // re-render so the new art appears immediately.
        BuddyManager.shared.$effectiveIdentity
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshModel()
            }
            .store(in: &cancellables)

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.rebuildWindowIfVisible()
            }
        }
    }

    // MARK: - Enabled State

    private func setRoaming(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            rebuildWindow()
            startTimer()
        } else {
            stopTimer()
            window?.orderOut(nil)
        }
    }

    /// Re-publishes the model so the hosted view re-evaluates (e.g. species swap).
    private func refreshModel() {
        objectWillChange.send()
    }

    // MARK: - Window

    /// Menu-bar band geometry, following the app idiom
    /// (`screen.frame.maxY - screen.visibleFrame.maxY`, cf. BuddiViewModel.chinHeight).
    /// The sprite is taller than the band, so the (transparent, click-through)
    /// window extends below the menu bar — the pet's head rides in the band
    /// while its body hangs over the desktop like a critter on a ledge.
    private static func bandFrame(on screen: NSScreen) -> CGRect {
        let bandHeight = screen.frame.maxY - screen.visibleFrame.maxY
        guard bandHeight > 0 else { return .zero }  // auto-hidden menu bar

        let overhang = PetRoamerView.spriteSize + 8
        return CGRect(
            x: screen.frame.minX,
            y: screen.visibleFrame.maxY - overhang,
            width: screen.frame.width,
            height: bandHeight + overhang
        )
    }

    private func rebuildWindow() {
        let oldWindow = window
        window = nil
        oldWindow?.orderOut(nil)
        oldWindow?.contentView = nil

        guard isEnabled,
              let screen = NSScreen.main,
              let newWindow = makeWindow(for: screen) else { return }

        window = newWindow
        model = PetRoamerModel()
        newWindow.orderFrontRegardless()
    }

    private func rebuildWindowIfVisible() {
        guard isEnabled else { return }
        rebuildWindow()
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow? {
        let frame = Self.bandFrame(on: screen)
        guard frame.height > 0 else { return nil }

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: PetRoamerView(roamer: self))
        if #available(macOS 13.0, *) {
            hostingView.sizingOptions = []
        }
        window.contentView = hostingView
        return window
    }

    // MARK: - Timer

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop; the tick is always main-thread.
            MainActor.assumeIsolated {
                self?.onTick()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func onTick() {
        guard isEnabled, let window, window.isVisible else { return }

        let bandWidth = window.frame.width
        // Walkable range keeps the 64pt sprite fully inside the window.
        let bounds = CGRect(
            x: 0,
            y: 0,
            width: max(0, bandWidth - PetRoamerView.spriteSize),
            height: window.frame.height
        )
        guard bounds.width > 0 else { return }

        var newModel = model
        newModel.tick(dt: 1.0 / 30.0, bounds: bounds)
        model = newModel
    }
}
