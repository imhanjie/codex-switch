import Foundation

public struct AuthInfo: Equatable, Sendable {
    public let email: String
    public let chatgptUserID: String
    public let chatgptAccountID: String
    public let recordKey: String
    public let accessToken: String
    public let refreshToken: String
    public let plan: String?
    public let authMode: String

    public init(
        email: String,
        chatgptUserID: String,
        chatgptAccountID: String,
        recordKey: String,
        accessToken: String,
        refreshToken: String,
        plan: String?,
        authMode: String
    ) {
        self.email = email
        self.chatgptUserID = chatgptUserID
        self.chatgptAccountID = chatgptAccountID
        self.recordKey = recordKey
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.plan = plan
        self.authMode = authMode
    }
}

public struct ManagedAccount: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let recordKey: String
    public let email: String
    public let plan: String?
    public let chatgptUserID: String
    public let chatgptAccountID: String
    public let authMode: String

    public init(
        recordKey: String,
        email: String,
        plan: String?,
        chatgptUserID: String,
        chatgptAccountID: String,
        authMode: String
    ) {
        self.recordKey = recordKey
        self.email = email
        self.plan = plan
        self.chatgptUserID = chatgptUserID
        self.chatgptAccountID = chatgptAccountID
        self.authMode = authMode
    }

    public var id: String {
        recordKey
    }

    public var shortKey: String {
        String(Base64URL.encode(recordKey).prefix(10))
    }

    enum CodingKeys: String, CodingKey {
        case recordKey = "record_key"
        case email
        case plan
        case chatgptUserID = "chatgpt_user_id"
        case chatgptAccountID = "chatgpt_account_id"
        case authMode = "auth_mode"
    }
}

public struct RegistryState: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersionValue: Int
    public var activeRecordKey: String?
    public var accounts: [ManagedAccount]

    public init(
        schemaVersionValue: Int = RegistryState.schemaVersion,
        activeRecordKey: String? = nil,
        accounts: [ManagedAccount] = []
    ) {
        self.schemaVersionValue = schemaVersionValue
        self.activeRecordKey = activeRecordKey
        self.accounts = accounts
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersionValue = "schema_version"
        case activeRecordKey = "active_record_key"
        case accounts
    }
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public let remainingPercent: Int
    public let windowMinutes: Int?
    public let resetAt: Date?

    public init(remainingPercent: Int, windowMinutes: Int?, resetAt: Date?) {
        self.remainingPercent = remainingPercent
        self.windowMinutes = windowMinutes
        self.resetAt = resetAt
    }
}

public struct UsageSummary: Codable, Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let weekly: UsageWindow?
    public let fetchedAt: Date

    public init(fiveHour: UsageWindow?, weekly: UsageWindow?, fetchedAt: Date) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.fetchedAt = fetchedAt
    }
}

public struct UsageRefreshResult: Equatable, Sendable {
    public let usages: [String: UsageSummary]
    public let failures: [String]
    public let successCount: Int

    public init(usages: [String: UsageSummary], failures: [String], successCount: Int) {
        self.usages = usages
        self.failures = failures
        self.successCount = successCount
    }

    public var hasSuccess: Bool {
        successCount > 0
    }
}

public struct DashboardSnapshot: Equatable, Sendable {
    public let accounts: [ManagedAccount]
    public let activeRecordKey: String?
    public let liveRecordKey: String?
    public let unmanagedLiveEmail: String?
    public let usageCache: [String: UsageSummary]
    public let liveErrorMessage: String?

    public init(
        accounts: [ManagedAccount],
        activeRecordKey: String?,
        liveRecordKey: String?,
        unmanagedLiveEmail: String?,
        usageCache: [String: UsageSummary],
        liveErrorMessage: String?
    ) {
        self.accounts = accounts
        self.activeRecordKey = activeRecordKey
        self.liveRecordKey = liveRecordKey
        self.unmanagedLiveEmail = unmanagedLiveEmail
        self.usageCache = usageCache
        self.liveErrorMessage = liveErrorMessage
    }
}

public struct LiveSyncResult: Equatable, Sendable {
    public let liveInfo: AuthInfo
    public let liveData: Data
    public let managed: Bool
    public let changed: Bool

    public init(liveInfo: AuthInfo, liveData: Data, managed: Bool, changed: Bool) {
        self.liveInfo = liveInfo
        self.liveData = liveData
        self.managed = managed
        self.changed = changed
    }
}
