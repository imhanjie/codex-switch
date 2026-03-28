import Foundation
import XCTest
@testable import CodexSwitchCore

final class CodexSwitchCoreTests: XCTestCase {
    func testAuthParserParsesValidChatGPTAuth() throws {
        let parser = AuthParser()
        let data = buildAuthData(email: "ONE@example.com", userID: "user-1", accountID: "acct-1", plan: "team")

        let (info, raw) = try parser.parseAuthData(data)

        XCTAssertEqual(raw, data)
        XCTAssertEqual(info.email, "one@example.com")
        XCTAssertEqual(info.recordKey, "user-1::acct-1")
        XCTAssertEqual(info.plan, "team")
    }

    func testAuthParserRejectsAPIKeyMode() {
        let parser = AuthParser()
        let data = Data(#"{"auth_mode":"apikey","OPENAI_API_KEY":"sk-test"}"#.utf8)

        XCTAssertThrowsError(try parser.parseAuthData(data)) { error in
            XCTAssertEqual((error as? CodexSwitchError)?.message, "当前只支持 ChatGPT 登录态，不支持 API Key 模式")
        }
    }

    func testCaptureCreatesRegistryAndSnapshot() async throws {
        let harness = try TestHarness()
        try harness.writeLiveAuth(buildAuthData(email: "capture@example.com", userID: "user-1", accountID: "acct-1"))

        let account = try await harness.service.captureCurrentAccount()
        let registry = try harness.store.loadRegistry(at: harness.paths)

        XCTAssertEqual(account.email, "capture@example.com")
        XCTAssertEqual(registry.activeRecordKey, "user-1::acct-1")
        XCTAssertEqual(registry.accounts.count, 1)
        XCTAssertEqual(try Data(contentsOf: harness.paths.snapshotURL(for: "user-1::acct-1")), try Data(contentsOf: harness.paths.liveAuthURL))
    }

    func testCaptureUpsertsChangedPlanAndSnapshot() async throws {
        let harness = try TestHarness()
        try harness.writeLiveAuth(buildAuthData(email: "same@example.com", userID: "user-1", accountID: "acct-1", plan: "team"))
        _ = try await harness.service.captureCurrentAccount()

        let updated = buildAuthData(email: "same@example.com", userID: "user-1", accountID: "acct-1", accessToken: "new-token", plan: "pro")
        try harness.writeLiveAuth(updated)
        _ = try await harness.service.captureCurrentAccount()

        let registry = try harness.store.loadRegistry(at: harness.paths)
        XCTAssertEqual(registry.accounts.first?.plan, "pro")
        XCTAssertEqual(try Data(contentsOf: harness.paths.snapshotURL(for: "user-1::acct-1")), updated)
    }

    func testLoadDashboardSyncsManagedLiveSnapshot() async throws {
        let harness = try TestHarness()
        let original = buildAuthData(email: "sync@example.com", userID: "user-sync", accountID: "acct-sync", accessToken: "old-token")
        try harness.writeLiveAuth(original)
        _ = try await harness.service.captureCurrentAccount()

        let refreshed = buildAuthData(email: "sync@example.com", userID: "user-sync", accountID: "acct-sync", accessToken: "new-token")
        try harness.writeLiveAuth(refreshed)

        let snapshot = try await harness.service.loadDashboard()

        XCTAssertNil(snapshot.liveErrorMessage)
        XCTAssertEqual(snapshot.activeRecordKey, "user-sync::acct-sync")
        XCTAssertEqual(try Data(contentsOf: harness.paths.snapshotURL(for: "user-sync::acct-sync")), refreshed)
    }

    func testSwitchWritesLiveAuthCreatesBackupAndSetsActiveRecord() async throws {
        let harness = try TestHarness()
        let authA = buildAuthData(email: "a@example.com", userID: "user-a", accountID: "acct-a")
        let authB = buildAuthData(email: "b@example.com", userID: "user-b", accountID: "acct-b")
        try harness.writeLiveAuth(authA)
        _ = try await harness.service.captureCurrentAccount()
        try harness.writeLiveAuth(authB)
        _ = try await harness.service.captureCurrentAccount()

        try harness.writeLiveAuth(authA)
        let switched = try await harness.service.switchAccount(recordKey: "user-b::acct-b")
        let registry = try harness.store.loadRegistry(at: harness.paths)
        let backups = try FileManager.default.contentsOfDirectory(at: harness.paths.backupsDirectoryURL, includingPropertiesForKeys: nil)

        XCTAssertEqual(switched.email, "b@example.com")
        XCTAssertEqual(try Data(contentsOf: harness.paths.liveAuthURL), authB)
        XCTAssertEqual(registry.activeRecordKey, "user-b::acct-b")
        XCTAssertEqual(backups.count, 1)
    }

    func testRemoveDeletesSnapshotAndClearsActivePointerOnly() async throws {
        let harness = try TestHarness()
        let authA = buildAuthData(email: "a@example.com", userID: "user-a", accountID: "acct-a")
        let authB = buildAuthData(email: "b@example.com", userID: "user-b", accountID: "acct-b")
        try harness.writeLiveAuth(authA)
        _ = try await harness.service.captureCurrentAccount()
        try harness.writeLiveAuth(authB)
        _ = try await harness.service.captureCurrentAccount()
        _ = try await harness.service.switchAccount(recordKey: "user-b::acct-b")

        let removed = try await harness.service.removeAccount(recordKey: "user-b::acct-b")
        let registry = try harness.store.loadRegistry(at: harness.paths)

        XCTAssertEqual(removed.email, "b@example.com")
        XCTAssertEqual(registry.activeRecordKey, nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.paths.snapshotURL(for: "user-b::acct-b").path))
        XCTAssertEqual(try Data(contentsOf: harness.paths.liveAuthURL), authB)
    }

    func testRefreshUsageUsesLiveOverrideWithoutRewritingSnapshot() async throws {
        let networking = RecordingUsageNetworking(
            responses: [
                "acct-live": .success((buildUsageResponse(primaryWindow: [
                    "used_percent": 20.0,
                    "limit_window_seconds": 18_000,
                    "reset_at": 1_700_400_000,
                ]), 200)),
            ]
        )
        let harness = try TestHarness(networking: networking)

        let snapshotAuth = buildAuthData(
            email: "live@example.com",
            userID: "user-live",
            accountID: "acct-live",
            accessToken: "snapshot-token"
        )
        try harness.writeLiveAuth(snapshotAuth)
        _ = try await harness.service.captureCurrentAccount()

        let liveAuth = buildAuthData(
            email: "live@example.com",
            userID: "user-live",
            accountID: "acct-live",
            accessToken: "live-token"
        )
        try harness.writeLiveAuth(liveAuth)

        let result = try await harness.service.refreshUsage()
        let requests = await networking.requests()

        XCTAssertTrue(result.hasSuccess)
        XCTAssertEqual(requests.map(\.accessToken), ["live-token"])
        XCTAssertEqual(try Data(contentsOf: harness.paths.snapshotURL(for: "user-live::acct-live")), snapshotAuth)
    }

    func testRefreshUsageToleratesPartialFailures() async throws {
        let networking = RecordingUsageNetworking(
            responses: [
                "acct-ok": .success((buildUsageResponse(primaryWindow: [
                    "used_percent": 30.0,
                    "limit_window_seconds": 18_000,
                    "reset_at": 1_700_500_000,
                ]), 200)),
                "acct-fail": .failure(CodexSwitchError("网络请求失败：boom")),
            ]
        )
        let harness = try TestHarness(networking: networking)
        try harness.writeLiveAuth(buildAuthData(email: "fail@example.com", userID: "user-fail", accountID: "acct-fail"))
        _ = try await harness.service.captureCurrentAccount()
        try harness.writeLiveAuth(buildAuthData(email: "ok@example.com", userID: "user-ok", accountID: "acct-ok"))
        _ = try await harness.service.captureCurrentAccount()

        let result = try await harness.service.refreshUsage()

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertNotNil(result.usages["user-ok::acct-ok"])
        XCTAssertNil(result.usages["user-fail::acct-fail"])
    }

    func testUsageParserSupportsExactAndFallbackWindows() throws {
        let exact = try UsageService.parseUsagePayload(
            [
                "rate_limit": [
                    "primary_window": [
                        "used_percent": 25.0,
                        "limit_window_seconds": 18_000,
                        "reset_at": 1_700_000_000,
                    ],
                    "secondary_window": [
                        "used_percent": 10.0,
                        "limit_window_seconds": 604_800,
                        "reset_at": 1_700_100_000,
                    ],
                ],
            ]
        )
        XCTAssertEqual(exact.fiveHour?.remainingPercent, 75)
        XCTAssertEqual(exact.weekly?.remainingPercent, 90)

        let fallback = try UsageService.parseUsagePayload(
            [
                "rate_limit": [
                    "primary_window": [
                        "used_percent": 40.0,
                        "limit_window_seconds": 7_200,
                        "reset_at": 1_700_200_000,
                    ],
                    "secondary_window": [
                        "used_percent": 5.0,
                        "limit_window_seconds": 14_400,
                        "reset_at": 1_700_300_000,
                    ],
                ],
            ]
        )
        XCTAssertEqual(fallback.fiveHour?.remainingPercent, 60)
        XCTAssertEqual(fallback.weekly?.remainingPercent, 95)
    }

    func testLoginCoordinatorReportsMissingBinary() async {
        let coordinator = LoginCoordinator(
            environment: [:],
            locator: FailingLocator(),
            runner: NoopLoginRunner()
        )

        do {
            try await coordinator.login()
            XCTFail("Expected login to fail")
        } catch let error as CodexSwitchError {
            XCTAssertEqual(error.message, "未找到 `codex` 命令，请先安装 Codex CLI。")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLoginNewAccountCapturesCurrentLiveAuth() async throws {
        let harness = try TestHarness(
            locator: StaticLocator(),
            runner: SuccessfulLoginRunner()
        )
        try harness.writeLiveAuth(buildAuthData(email: "login@example.com", userID: "user-login", accountID: "acct-login"))

        let account = try await harness.service.loginNewAccount()
        let registry = try harness.store.loadRegistry(at: harness.paths)

        XCTAssertEqual(account.email, "login@example.com")
        XCTAssertEqual(registry.activeRecordKey, "user-login::acct-login")
        XCTAssertEqual(registry.accounts.count, 1)
    }
}

private struct TestHarness {
    let root: URL
    let paths: AppPaths
    let service: CodexSwitchService

    var store: AccountStore {
        AccountStore()
    }

    init(
        networking: RecordingUsageNetworking = RecordingUsageNetworking(responses: [:]),
        locator: CodexBinaryLocating = StaticLocator(),
        runner: CodexLoginRunning = SuccessfulLoginRunner()
    ) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let codexHome = root.appendingPathComponent("codex-home", isDirectory: true)
        let switcherHome = root.appendingPathComponent("switcher-home", isDirectory: true)
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: switcherHome, withIntermediateDirectories: true)
        paths = AppPaths(codexHome: codexHome, switcherHome: switcherHome)
        let usageService = UsageService(networking: networking)
        let loginCoordinator = LoginCoordinator(environment: [:], locator: locator, runner: runner)
        service = CodexSwitchService(paths: paths, usageService: usageService, loginCoordinator: loginCoordinator)
    }

    func writeLiveAuth(_ data: Data) throws {
        try data.write(to: paths.liveAuthURL, options: .atomic)
    }
}

private actor RecordingUsageNetworking: UsageNetworking {
    typealias Response = Result<(Data, Int), CodexSwitchError>

    private let responses: [String: Response]
    private var capturedRequests: [(accessToken: String, accountID: String)] = []

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> (data: Data, statusCode: Int) {
        capturedRequests.append((accessToken: accessToken, accountID: accountID))
        switch responses[accountID] ?? .failure(CodexSwitchError("missing response")) {
        case let .success(response):
            return (data: response.0, statusCode: response.1)
        case let .failure(error):
            throw error
        }
    }

    func requests() -> [(accessToken: String, accountID: String)] {
        capturedRequests
    }
}

private struct FailingLocator: CodexBinaryLocating {
    func locate(environment: [String : String]) throws -> URL {
        throw CodexSwitchError("未找到 `codex` 命令，请先安装 Codex CLI。")
    }
}

private struct StaticLocator: CodexBinaryLocating {
    func locate(environment: [String : String]) throws -> URL {
        URL(fileURLWithPath: "/usr/bin/codex")
    }
}

private struct SuccessfulLoginRunner: CodexLoginRunning {
    func runLogin(executableURL: URL, environment: [String : String]) async throws -> ProcessOutput {
        ProcessOutput(exitCode: 0, stdout: "", stderr: "")
    }
}

private struct NoopLoginRunner: CodexLoginRunning {
    func runLogin(executableURL: URL, environment: [String : String]) async throws -> ProcessOutput {
        ProcessOutput(exitCode: 0, stdout: "", stderr: "")
    }
}

private func buildAuthData(
    email: String,
    userID: String,
    accountID: String,
    accessToken: String = "access-token",
    refreshToken: String = "refresh-token",
    plan: String? = "team"
) -> Data {
    let header = base64URL(["alg": "RS256", "typ": "JWT"])
    var authClaim: [String: Any] = [
        "chatgpt_account_id": accountID,
        "chatgpt_user_id": userID,
    ]
    if let plan {
        authClaim["chatgpt_plan_type"] = plan
    }
    let payload = base64URL([
        "email": email,
        "https://api.openai.com/auth": authClaim,
    ])
    let token = "\(header).\(payload).sig"

    let json: [String: Any] = [
        "auth_mode": "chatgpt",
        "OPENAI_API_KEY": NSNull(),
        "tokens": [
            "id_token": token,
            "access_token": accessToken,
            "refresh_token": refreshToken,
            "account_id": accountID,
        ],
        "last_refresh": "2026-03-27T00:00:00Z",
    ]

    return try! JSONSerialization.data(withJSONObject: json)
}

private func buildUsageResponse(
    primaryWindow: [String: Any]? = nil,
    secondaryWindow: [String: Any]? = nil
) -> Data {
    var rateLimit: [String: Any] = [:]
    if let primaryWindow {
        rateLimit["primary_window"] = primaryWindow
    }
    if let secondaryWindow {
        rateLimit["secondary_window"] = secondaryWindow
    }
    return try! JSONSerialization.data(withJSONObject: ["rate_limit": rateLimit])
}

private func base64URL(_ value: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: value)
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
