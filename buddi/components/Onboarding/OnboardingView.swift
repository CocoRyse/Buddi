//
//  OnboardingView.swift
//  buddi
//
//

import SwiftUI
import AVFoundation

enum OnboardingStep {
    case welcome
    case meetBuddy
    case hooksInstall
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case accessibilityPermission
    case musicPermission
    case finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .meetBuddy
                    }
                }
                .transition(.opacity)

            case .meetBuddy:
                MeetBuddyOnboardingView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .hooksInstall
                    }
                }
                .transition(.opacity)

            case .hooksInstall:
                HooksInstallOnboardingView {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        step = .cameraPermission
                    }
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "Buddi includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .calendarPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .calendarPermission
                        }
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "Buddi can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                        Task {
                                await requestCalendarPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .remindersPermission
                                }
                        }
                    },
                    onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .remindersPermission
                            }
                    }
                )
                .transition(.opacity)

                case .remindersPermission:
                    PermissionRequestView(
                        icon: Image(systemName: "checklist"),
                        title: "Enable Reminders Access",
                        description: "Buddi can show your scheduled reminders alongside your calendar events. Access to Reminders is needed to display your reminders.",
                        privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                        onAllow: {
                            Task {
                                await requestRemindersPermission()
                                withAnimation(.easeInOut(duration: 0.6)) {
                                    step = .accessibilityPermission
                                }
                            }
                        },
                        onSkip: {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .accessibilityPermission
                            }
                        }
                    )
                    .transition(.opacity)
                
            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access is required to replace system notifications with the Buddi HUD. This allows the app to intercept media and brightness events to display custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        Task {
                            await requestAccessibilityPermission()
                            withAnimation(.easeInOut(duration: 0.6)) {
                                step = .musicPermission
                            }
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            step = .musicPermission
                        }
                    }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            BuddiViewCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestCalendarPermission() async {
        _ = try? await calendarService.requestAccess(to: .event)
    }

    func requestRemindersPermission() async {
        _ = try? await calendarService.requestAccess(to: .reminder)
    }
    
    func requestAccessibilityPermission() async {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - Meet Buddy

struct MeetBuddyOnboardingView: View {
    let onContinue: () -> Void
    private var identity: BuddyIdentity { BuddyManager.shared.effectiveIdentity }

    var body: some View {
        VStack(spacing: 28) {
            BuddySpriteView(
                animator: BuddyManager.shared.animator,
                identity: identity,
                asciiFontSize: 18
            )
            .padding(.top, 32)

            Text(identity.name ?? identity.species.rawValue.capitalized)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(nsColor: identity.rarity.nsColor))

            Text("\(identity.rarity.rawValue.capitalized) \(identity.species.rawValue.capitalized)")
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)

            Text("Your buddy is unique to you — generated from your system identity.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}

// MARK: - Hooks Install

struct HooksInstallOnboardingView: View {
    @State private var installed = HookInstaller.isInstalled()
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "link.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 56)
                .foregroundColor(.effectiveAccent)
                .padding(.top, 32)

            Text("Connect to Claude Code")
                .font(.title)
                .fontWeight(.semibold)

            Text("Install hooks to let Buddi monitor your Claude Code sessions, show approval requests, and track usage.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if installed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Hooks installed")
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    HookInstaller.installIfNeeded()
                    installed = HookInstaller.isInstalled()
                } label: {
                    Text("Install Hooks")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.secondary)
                Text("Hooks only send session events to Buddi. No data leaves your machine.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal)

            Button {
                onContinue()
            } label: {
                Text(installed ? "Continue" : "Skip for now")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
}
