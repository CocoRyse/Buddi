import Combine
import Foundation
import Security

// MARK: - Models

struct UsageData: Equatable, Codable {
    var fiveHour: QuotaPeriod?
    var sevenDay: QuotaPeriod?

    static let empty = UsageData()
}

struct QuotaPeriod: Equatable, Codable {
    let utilization: Double     // 0-100, percent used
    let resetsAt: Date?
}

enum UsageSource: String, Codable, Equatable {
    case glm
    case anthropicOAuth
}

// MARK: - Usage Service

@MainActor
final class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published private(set) var usage = UsageData.empty
    @Published private(set) var isAvailable = false
    @Published private(set) var activeSource: UsageSource?
    @Published private(set) var planTier: String?

    private enum UsageProvider {
        case glm(apiKey: String, endpoint: URL)
        case anthropicOAuth(token: String)
    }

    private var pollTimer: Timer?
    private var pollTask: Task<Void, Never>?
    private let baseInterval: TimeInterval = 300
    private var currentInterval: TimeInterval = 300
    private var backoffCount = 0
    private var consecutiveFailures = 0

    private static let isoFormatterFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterBasic = ISO8601DateFormatter()

    private init() {}

    func startPolling() {
        guard pollTimer == nil else { return }
        loadCache()
        poll()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollTask?.cancel()
        pollTask = nil
        backoffCount = 0
        consecutiveFailures = 0
        currentInterval = baseInterval
    }

    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    private func poll() {
        pollTask = Task {
            guard let provider = Self.resolveProvider() else {
                isAvailable = false
                activeSource = nil
                planTier = nil
                scheduleNextPoll()
                return
            }

            if !isAvailable { isAvailable = true }

            do {
                switch provider {
                case let .glm(apiKey, endpoint):
                    let result = try await Self.fetchGLMUsage(apiKey: apiKey, endpoint: endpoint)
                    usage = result.usage
                    planTier = result.planTier
                    activeSource = .glm
                case let .anthropicOAuth(token):
                    usage = try await Self.fetchUsage(token: token)
                    planTier = nil
                    activeSource = .anthropicOAuth
                }
                consecutiveFailures = 0
                backoffCount = 0
                currentInterval = baseInterval
                saveCache()
            } catch let error as URLError where error.code.rawValue == 429 {
                backoffCount += 1
                currentInterval = min(1800, baseInterval * pow(2.0, Double(backoffCount)))
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures > 5 && usage.fiveHour == nil && usage.sevenDay == nil {
                    isAvailable = false
                }
            }
            scheduleNextPoll()
        }
    }

    // MARK: - Cache

    private static let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Buddi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-cache.json")
    }()

    private struct CachedUsage: Codable {
        let usage: UsageData
        let fetchedAt: Date
        let source: UsageSource?
        let planTier: String?
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cached = try? JSONDecoder().decode(CachedUsage.self, from: data) else { return }
        usage = cached.usage
        activeSource = cached.source
        planTier = cached.planTier
        isAvailable = true
    }

    private func saveCache() {
        let cached = CachedUsage(usage: usage, fetchedAt: Date(), source: activeSource, planTier: planTier)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: - Provider Resolution

    private static func resolveProvider() -> UsageProvider? {
        if let creds = readGLMCredentials() {
            return .glm(apiKey: creds.apiKey, endpoint: creds.endpoint)
        }
        if let token = readOAuthToken() {
            return .anthropicOAuth(token: token)
        }
        return nil
    }

    /// GLM Coding Plan credentials live in ~/.claude/settings.json (env block),
    /// the same place Claude Code reads them from. GUI apps don't inherit shell env.
    private static func readGLMCredentials() -> (apiKey: String, endpoint: URL)? {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")

        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any],
              let rawKey = env["ANTHROPIC_AUTH_TOKEN"] as? String else { return nil }

        let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return nil }

        let baseURL = (env["ANTHROPIC_BASE_URL"] as? String).flatMap(URL.init(string:))
        return (apiKey, monitorEndpoint(for: baseURL))
    }

    /// The z.ai quota monitor runs on the platform root, not the Anthropic-compat base.
    private static func monitorEndpoint(for baseURL: URL?) -> URL {
        let root = (baseURL?.host == "open.bigmodel.cn") ? "https://open.bigmodel.cn" : "https://api.z.ai"
        return URL(string: root + "/api/monitor/usage/quota/limit")!
    }

    // MARK: - Keychain

    private static func readOAuthToken() -> String? {
        // Primary: /usr/bin/security CLI (avoids ACL dialog)
        if let json = readKeychainViaCLI(),
           let token = extractToken(from: json) {
            return token
        }

        // Fallback: Security.framework
        if let json = readKeychainViaFramework(),
           let token = extractToken(from: json) {
            return token
        }

        return nil
    }

    private static func readKeychainViaCLI() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch { return nil }
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func readKeychainViaFramework() -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private static func extractToken(from json: [String: Any]) -> String? {
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let rawToken = oauth["accessToken"] as? String else { return nil }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: - API Call

    /// GLM Coding Plan quota (z.ai / BigModel monitor API; used by Z.ai's own usage plugin).
    /// The Authorization header carries the raw API key — no Bearer prefix.
    private static func fetchGLMUsage(apiKey: String, endpoint: URL) async throws -> (usage: UsageData, planTier: String?) {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("en-US,en", forHTTPHeaderField: "Accept-Language")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            throw URLError(.init(rawValue: http.statusCode))
        }

        let decoded: GLMQuotaResponse
        do {
            decoded = try JSONDecoder().decode(GLMQuotaResponse.self, from: data)
        } catch {
            throw URLError(.cannotParseResponse)
        }

        guard let quotaData = decoded.data,
              let usage = mapGLM(quotaData) else {
            throw URLError(.cannotParseResponse)
        }

        return (usage, quotaData.level)
    }

    private static func mapGLM(_ data: GLMQuotaData) -> UsageData? {
        // TIME_LIMIT entries are the monthly MCP lane — not plan windows.
        let windows = (data.limits ?? []).filter { $0.type == "TOKENS_LIMIT" || $0.type == "CREDIT_LIMIT" }

        var fiveHour: QuotaPeriod?
        var sevenDay: QuotaPeriod?

        var unassigned: [GLMLimit] = []
        for limit in windows {
            if limit.unit == 3, fiveHour == nil {
                fiveHour = quotaPeriod(from: limit)
            } else if limit.unit == 6, sevenDay == nil {
                sevenDay = quotaPeriod(from: limit)
            } else if limit.unit == nil {
                unassigned.append(limit)
            }
        }

        // Fallback when `unit` is absent: earliest reset = 5h window, next = weekly.
        if fiveHour == nil || sevenDay == nil {
            for limit in unassigned.sorted(by: { ($0.nextResetTime ?? 0) < ($1.nextResetTime ?? 0) }) {
                if fiveHour == nil {
                    fiveHour = quotaPeriod(from: limit)
                } else if sevenDay == nil {
                    sevenDay = quotaPeriod(from: limit)
                }
            }
        }

        guard fiveHour != nil || sevenDay != nil else { return nil }
        return UsageData(fiveHour: fiveHour, sevenDay: sevenDay)
    }

    private static func quotaPeriod(from limit: GLMLimit) -> QuotaPeriod {
        let utilization = min(max(limit.percentage ?? 0, 0), 100)
        let resetsAt = limit.nextResetTime.map { Date(timeIntervalSince1970: $0 / 1000) }  // epoch ms
        return QuotaPeriod(utilization: utilization, resetsAt: resetsAt)
    }

    private struct GLMQuotaResponse: Decodable {
        let code: Int?
        let success: Bool?
        let data: GLMQuotaData?
    }

    private struct GLMQuotaData: Decodable {
        let level: String?
        let limits: [GLMLimit]?
    }

    private struct GLMLimit: Decodable {
        let type: String?
        let percentage: Double?
        let unit: Int?
        let nextResetTime: Double?   // epoch milliseconds
    }

    private static func fetchUsage(token: String) async throws -> UsageData {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            throw URLError(.init(rawValue: http.statusCode))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        return UsageData(
            fiveHour: parseQuotaPeriod(json["five_hour"]),
            sevenDay: parseQuotaPeriod(json["seven_day"])
        )
    }

    private static func parseQuotaPeriod(_ value: Any?) -> QuotaPeriod? {
        guard let dict = value as? [String: Any],
              let utilization = dict["utilization"] as? Double else { return nil }

        var resetsAt: Date?
        if let dateStr = dict["resets_at"] as? String {
            resetsAt = isoFormatterFrac.date(from: dateStr) ?? isoFormatterBasic.date(from: dateStr)
        }

        return QuotaPeriod(utilization: utilization, resetsAt: resetsAt)
    }
}
