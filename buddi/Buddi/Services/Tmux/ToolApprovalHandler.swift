//
//  ToolApprovalHandler.swift
//  Buddi
//
//  Handles Claude tool approval operations via tmux
//

import Foundation
import os

/// Handles tool approval and rejection for Claude instances
actor ToolApprovalHandler {
    static let shared = ToolApprovalHandler()

    /// Logger for tool approval (nonisolated static for cross-context access)
    nonisolated static let logger = os.Logger(subsystem: "com.cocoryse.buddi", category: "Approval")

    private init() {}

    /// Approve a tool once (sends '1' + Enter)
    func approveOnce(target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: "1", pressEnter: true)
    }

    /// Approve a tool always (sends '2' + Enter)
    func approveAlways(target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: "2", pressEnter: true)
    }

    /// Reject a tool with optional message
    func reject(target: TmuxTarget, message: String? = nil) async -> Bool {
        // First send 'n' + Enter to reject
        guard await sendKeys(to: target, keys: "n", pressEnter: true) else {
            return false
        }

        // If there's a message, send it after a brief delay
        if let message = message, !message.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
            return await sendKeys(to: target, keys: message, pressEnter: true)
        }

        return true
    }

    /// Send a message to a tmux target
    func sendMessage(_ message: String, to target: TmuxTarget) async -> Bool {
        await sendKeys(to: target, keys: message, pressEnter: true)
    }

    // MARK: - Private Methods

    private func sendKeys(to target: TmuxTarget, keys: String, pressEnter: Bool) async -> Bool {
        switch target.multiplexer {
        case .tmux:
            return await sendTmuxKeys(to: target, keys: keys, pressEnter: pressEnter)
        case .cmux:
            return await sendCmuxKeys(to: target, keys: keys, pressEnter: pressEnter)
        }
    }

    private func sendTmuxKeys(to target: TmuxTarget, keys: String, pressEnter: Bool) async -> Bool {
        guard let tmuxPath = await TmuxPathFinder.shared.getTmuxPath() else {
            return false
        }

        // tmux send-keys needs literal text and Enter as separate arguments
        // Use -l flag to send keys literally (prevents interpreting special chars)
        let targetStr = target.targetString
        let textArgs = ["send-keys", "-t", targetStr, "-l", keys]

        do {
            Self.logger.debug("Sending text to tmux \(targetStr, privacy: .public)")
            _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: textArgs)

            // Send Enter as a separate command if needed
            if pressEnter {
                Self.logger.debug("Sending Enter key to tmux")
                let enterArgs = ["send-keys", "-t", targetStr, "Enter"]
                _ = try await ProcessExecutor.shared.run(tmuxPath, arguments: enterArgs)
            }
            return true
        } catch {
            Self.logger.error("tmux error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func sendCmuxKeys(to target: TmuxTarget, keys: String, pressEnter: Bool) async -> Bool {
        guard let cmuxPath = await TmuxPathFinder.shared.getCmuxPath() else {
            return false
        }

        guard let workspace = target.cmuxWorkspaceRef,
              let surface = target.cmuxSurfaceRef else {
            Self.logger.error("Invalid cmux target: missing workspace or surface ref")
            return false
        }

        let password = Self.readCmuxSocketPassword()

        do {
            Self.logger.debug("Sending text to cmux \(surface, privacy: .public)")
            let sendArgs = password != nil
                ? ["--password", password!, "send", "--workspace", workspace, "--surface", surface, keys]
                : ["send", "--workspace", workspace, "--surface", surface, keys]
            _ = try await ProcessExecutor.shared.run(cmuxPath, arguments: sendArgs)

            if pressEnter {
                Self.logger.debug("Sending Enter key to cmux")
                let keyArgs = password != nil
                    ? ["--password", password!, "send-key", "--workspace", workspace, "--surface", surface, "return"]
                    : ["send-key", "--workspace", workspace, "--surface", surface, "return"]
                _ = try await ProcessExecutor.shared.run(cmuxPath, arguments: keyArgs)
            }
            return true
        } catch {
            Self.logger.error("cmux error: \(error.localizedDescription, privacy: .public). Set cmux socket mode to 'Automation' in cmux Settings to allow buddi access.")
            return false
        }
    }

    /// Read cmux socket password from the standard file location
    private static func readCmuxSocketPassword() -> String? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let passwordFile = appSupport
            .appendingPathComponent("cmux", isDirectory: true)
            .appendingPathComponent("socket-control-password", isDirectory: false)
        guard let data = try? Data(contentsOf: passwordFile),
              let password = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines),
              !password.isEmpty else {
            return nil
        }
        return password
    }
}
