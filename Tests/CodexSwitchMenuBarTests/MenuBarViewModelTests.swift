import Combine
import Foundation
import XCTest
@testable import CodexSwitchCore
@testable import CodexSwitchMenuBar

@MainActor
final class MenuBarViewModelTests: XCTestCase {
    func testLoadPanelDoesNotTriggerUsageRefresh() async throws {
        let service = MenuBarServiceStub(dashboardSnapshot: makeDashboardSnapshot())
        let scheduler = ManualUsageRefreshScheduler()
        let viewModel = MenuBarViewModel(service: service, autoRefreshInterval: 300, scheduler: scheduler)

        viewModel.loadPanel()
        await waitForExpectations()

        let loadDashboardCallCount = await service.loadDashboardCallCount()
        let refreshUsageCallCount = await service.refreshUsageCallCount()
        XCTAssertEqual(loadDashboardCallCount, 1)
        XCTAssertEqual(refreshUsageCallCount, 0)
        XCTAssertEqual(viewModel.accounts.count, 1)
    }

    func testManualRefreshShowsSuccessNotice() async throws {
        let service = MenuBarServiceStub(refreshUsageResult: makeUsageRefreshResult())
        let scheduler = ManualUsageRefreshScheduler()
        let viewModel = MenuBarViewModel(service: service, autoRefreshInterval: 300, scheduler: scheduler)

        viewModel.refreshUsage(force: true)
        await waitForExpectations()

        let refreshUsageCallCount = await service.refreshUsageCallCount()
        XCTAssertEqual(refreshUsageCallCount, 1)
        XCTAssertEqual(viewModel.notice, .success("额度已刷新"))
    }

    func testAutomaticRefreshRunsSilently() async throws {
        let service = MenuBarServiceStub(refreshUsageResult: makeUsageRefreshResult())
        let scheduler = ManualUsageRefreshScheduler()
        let viewModel = MenuBarViewModel(service: service, autoRefreshInterval: 300, scheduler: scheduler)

        scheduler.fire()
        await waitForExpectations()

        let refreshUsageCallCount = await service.refreshUsageCallCount()
        XCTAssertEqual(refreshUsageCallCount, 1)
        XCTAssertNil(viewModel.notice)
    }

    func testAutomaticRefreshSkipsWhenRefreshAlreadyRunning() async throws {
        let service = MenuBarServiceStub(refreshUsageResult: makeUsageRefreshResult(), refreshDelay: 200_000_000)
        let scheduler = ManualUsageRefreshScheduler()
        let viewModel = MenuBarViewModel(service: service, autoRefreshInterval: 300, scheduler: scheduler)

        scheduler.fire()
        await waitUntil { viewModel.isRefreshingUsage }
        scheduler.fire()
        try await Task.sleep(nanoseconds: 250_000_000)

        let refreshUsageCallCount = await service.refreshUsageCallCount()
        XCTAssertEqual(refreshUsageCallCount, 1)
    }

    private func waitForExpectations() async {
        for _ in 0..<20 {
            await Task.yield()
        }
    }

    private func waitUntil(timeoutNanoseconds: UInt64 = 1_000_000_000, condition: @escaping @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(timeoutNanoseconds)))
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition was not met before timeout")
    }

    private func makeDashboardSnapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            accounts: [
                ManagedAccount(
                    recordKey: "user-1::acct-1",
                    email: "one@example.com",
                    plan: "team",
                    chatgptUserID: "user-1",
                    chatgptAccountID: "acct-1",
                    authMode: "chatgpt"
                ),
            ],
            activeRecordKey: "user-1::acct-1",
            liveRecordKey: "user-1::acct-1",
            unmanagedLiveEmail: nil,
            usageCache: [:],
            liveErrorMessage: nil
        )
    }

    private func makeUsageRefreshResult() -> UsageRefreshResult {
        UsageRefreshResult(
            usages: [
                "user-1::acct-1": UsageSummary(
                    fiveHour: UsageWindow(remainingPercent: 80, windowMinutes: 300, resetAt: nil),
                    weekly: UsageWindow(remainingPercent: 90, windowMinutes: 10_080, resetAt: nil),
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
                ),
            ],
            failures: [],
            successCount: 1
        )
    }
}

private actor MenuBarServiceStub: MenuBarServicing {
    private let dashboardSnapshot: DashboardSnapshot
    private let refreshUsageResult: UsageRefreshResult
    private let refreshDelay: UInt64

    private(set) var loadDashboardCallCount = 0
    private(set) var refreshUsageCallCount = 0

    init(
        dashboardSnapshot: DashboardSnapshot = DashboardSnapshot(
            accounts: [],
            activeRecordKey: nil,
            liveRecordKey: nil,
            unmanagedLiveEmail: nil,
            usageCache: [:],
            liveErrorMessage: nil
        ),
        refreshUsageResult: UsageRefreshResult = UsageRefreshResult(usages: [:], failures: [], successCount: 0),
        refreshDelay: UInt64 = 0
    ) {
        self.dashboardSnapshot = dashboardSnapshot
        self.refreshUsageResult = refreshUsageResult
        self.refreshDelay = refreshDelay
    }

    func loadDashboard() async throws -> DashboardSnapshot {
        loadDashboardCallCount += 1
        return dashboardSnapshot
    }

    func captureCurrentAccount() async throws -> ManagedAccount {
        throw CodexSwitchError("unused")
    }

    func loginNewAccount() async throws -> ManagedAccount {
        throw CodexSwitchError("unused")
    }

    func switchAccount(recordKey: String) async throws -> ManagedAccount {
        throw CodexSwitchError("unused")
    }

    func removeAccount(recordKey: String) async throws -> ManagedAccount {
        throw CodexSwitchError("unused")
    }

    func refreshUsage() async throws -> UsageRefreshResult {
        refreshUsageCallCount += 1
        if refreshDelay > 0 {
            try await Task.sleep(nanoseconds: refreshDelay)
        }
        return refreshUsageResult
    }

    func loadDashboardCallCount() -> Int {
        loadDashboardCallCount
    }

    func refreshUsageCallCount() -> Int {
        refreshUsageCallCount
    }
}

private final class ManualUsageRefreshScheduler: UsageRefreshScheduling {
    private var action: (@MainActor () -> Void)?

    @MainActor
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyCancellable {
        self.action = action
        return AnyCancellable {}
    }

    func fire() {
        action?()
    }
}
