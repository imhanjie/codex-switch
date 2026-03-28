import Foundation

public protocol UsageNetworking: Sendable {
    func fetchUsage(accessToken: String, accountID: String) async throws -> (data: Data, statusCode: Int)
}

public struct URLSessionUsageNetworking: UsageNetworking {
    private let session: URLSession

    public init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 5
            configuration.timeoutIntervalForResource = 5
            self.session = URLSession(configuration: configuration)
        }
    }

    public func fetchUsage(accessToken: String, accountID: String) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("codex-switch", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CodexSwitchError("usage 接口响应格式不正确")
            }
            return (data, httpResponse.statusCode)
        } catch let error as URLError where error.code == .timedOut {
            throw CodexSwitchError("网络请求失败：请求超时")
        } catch let error as URLError {
            throw CodexSwitchError("网络请求失败：\(error.localizedDescription)")
        } catch let error as CodexSwitchError {
            throw error
        } catch {
            throw CodexSwitchError("网络请求失败：\(error.localizedDescription)")
        }
    }
}

public struct UsageService: Sendable {
    public static let maxConcurrentRequests = 8

    private let authParser: AuthParser
    private let networking: UsageNetworking

    public init(authParser: AuthParser = AuthParser(), networking: UsageNetworking = URLSessionUsageNetworking()) {
        self.authParser = authParser
        self.networking = networking
    }

    public func fetchUsage(from authData: Data, fetchedAt: Date = Date()) async throws -> UsageSummary {
        let (info, _) = try authParser.parseAuthData(authData)
        let response = try await networking.fetchUsage(accessToken: info.accessToken, accountID: info.chatgptAccountID)
        guard response.statusCode == 200 else {
            throw CodexSwitchError("usage 接口返回 HTTP \(response.statusCode)")
        }

        let payload: Any
        do {
            payload = try JSONSerialization.jsonObject(with: response.data)
        } catch {
            throw CodexSwitchError("usage 接口响应不是合法的 JSON")
        }

        return try Self.parseUsagePayload(payload, fetchedAt: fetchedAt)
    }

    public static func parseUsagePayload(_ payload: Any, fetchedAt: Date = Date()) throws -> UsageSummary {
        guard let payload = payload as? [String: Any] else {
            throw CodexSwitchError("usage 接口响应格式不正确")
        }
        guard let rateLimit = payload["rate_limit"] as? [String: Any] else {
            throw CodexSwitchError("usage 响应缺少可用额度窗口")
        }

        let primary = parseWindow(rateLimit["primary_window"])
        let secondary = parseWindow(rateLimit["secondary_window"])
        let fiveHour = selectWindow(primary, secondary, targetMinutes: 300, fallback: primary)
        let weekly = selectWindow(primary, secondary, targetMinutes: 10_080, fallback: secondary)

        guard fiveHour != nil || weekly != nil else {
            throw CodexSwitchError("usage 响应缺少可用额度窗口")
        }

        return UsageSummary(fiveHour: fiveHour, weekly: weekly, fetchedAt: fetchedAt)
    }

    private static func parseWindow(_ payload: Any?) -> UsageWindow? {
        guard let payload = payload as? [String: Any] else {
            return nil
        }

        guard let usedPercent = coerceDouble(payload["used_percent"]) else {
            return nil
        }

        let remainingPercent = clampPercent(100 - usedPercent)
        let windowSeconds = coerceInt(payload["limit_window_seconds"])
        let resetAt = coerceInt(payload["reset_at"])

        return UsageWindow(
            remainingPercent: remainingPercent,
            windowMinutes: minutes(fromSeconds: windowSeconds),
            resetAt: resetAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
        )
    }

    private static func selectWindow(
        _ primary: UsageWindow?,
        _ secondary: UsageWindow?,
        targetMinutes: Int,
        fallback: UsageWindow?
    ) -> UsageWindow? {
        for window in [primary, secondary] {
            if window?.windowMinutes == targetMinutes {
                return window
            }
        }
        return fallback
    }

    private static func coerceDouble(_ value: Any?) -> Double? {
        switch value {
        case let number as Double:
            return number
        case let number as Int:
            return Double(number)
        case let number as NSNumber:
            return number.doubleValue
        default:
            return nil
        }
    }

    private static func coerceInt(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as Double:
            return Int(number)
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }

    private static func minutes(fromSeconds seconds: Int?) -> Int? {
        guard let seconds, seconds > 0 else {
            return nil
        }
        return (seconds + 59) / 60
    }

    private static func clampPercent(_ value: Double) -> Int {
        if value <= 0 { return 0 }
        if value >= 100 { return 100 }
        return Int(value)
    }
}
