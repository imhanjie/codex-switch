import AppKit
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

        let loadDashboardCallCount = await service.recordedLoadDashboardCallCount()
        let refreshUsageCallCount = await service.recordedRefreshUsageCallCount()
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

        let refreshUsageCallCount = await service.recordedRefreshUsageCallCount()
        XCTAssertEqual(refreshUsageCallCount, 1)
        XCTAssertEqual(viewModel.notice, .success("额度已刷新"))
        XCTAssertEqual(
            viewModel.lastUsageRefreshText,
            UsageDisplayFormatter.lastRefreshText(for: Date(timeIntervalSince1970: 1_700_000_000))
        )
    }

    func testManualRefreshResetsAutoRefreshCountdown() async throws {
        let service = MenuBarServiceStub(refreshUsageResult: makeUsageRefreshResult())
        let scheduler = ManualUsageRefreshScheduler()
        let viewModel = MenuBarViewModel(service: service, autoRefreshInterval: 300, scheduler: scheduler)

        let initialScheduleCount = scheduler.recordedScheduleCount()
        XCTAssertEqual(initialScheduleCount, 1)
        viewModel.refreshUsage(force: true)
        await waitForExpectations()

        let rescheduledCount = scheduler.recordedScheduleCount()
        XCTAssertEqual(rescheduledCount, 2)

        scheduler.fire(at: 0)
        await waitForExpectations()
        let callCountAfterOldTimerFire = await service.recordedRefreshUsageCallCount()
        XCTAssertEqual(callCountAfterOldTimerFire, 1)

        scheduler.fire(at: 1)
        await waitForExpectations()
        let callCountAfterNewTimerFire = await service.recordedRefreshUsageCallCount()
        XCTAssertEqual(callCountAfterNewTimerFire, 2)
    }

    func testAutomaticRefreshRunsSilently() async throws {
        let service = MenuBarServiceStub(refreshUsageResult: makeUsageRefreshResult())
        let scheduler = ManualUsageRefreshScheduler()
        let viewModel = MenuBarViewModel(service: service, autoRefreshInterval: 300, scheduler: scheduler)

        scheduler.fire()
        await waitForExpectations()

        let refreshUsageCallCount = await service.recordedRefreshUsageCallCount()
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

        let refreshUsageCallCount = await service.recordedRefreshUsageCallCount()
        XCTAssertEqual(refreshUsageCallCount, 1)
    }

    func testLastUsageRefreshTextUsesNewestCachedUsageTimestamp() async throws {
        let service = MenuBarServiceStub(dashboardSnapshot: makeDashboardSnapshotWithUsageCache())
        let scheduler = ManualUsageRefreshScheduler()
        let viewModel = MenuBarViewModel(service: service, autoRefreshInterval: 300, scheduler: scheduler)

        viewModel.loadPanel()
        await waitForExpectations()

        XCTAssertEqual(
            viewModel.lastUsageRefreshText,
            UsageDisplayFormatter.lastRefreshText(for: Date(timeIntervalSince1970: 1_700_001_100))
        )
    }

    func testLoginOnlyDisablesLoginAction() async throws {
        let service = MenuBarServiceStub(
            dashboardSnapshot: makeDashboardSnapshot(),
            refreshUsageResult: makeUsageRefreshResult(),
            loginResult: ManagedAccount(
                recordKey: "user-2::acct-2",
                email: "two@example.com",
                plan: "team",
                chatgptUserID: "user-2",
                chatgptAccountID: "acct-2",
                authMode: "chatgpt"
            ),
            loginDelay: 200_000_000
        )
        let scheduler = ManualUsageRefreshScheduler()
        let viewModel = MenuBarViewModel(service: service, autoRefreshInterval: 300, scheduler: scheduler)

        viewModel.loginNewAccount()
        await waitUntil { viewModel.isRunningLogin }

        XCTAssertFalse(viewModel.canLoginNewAccount)
        XCTAssertTrue(viewModel.canCaptureCurrentAccount)
        XCTAssertTrue(viewModel.canSwitchAccounts)
        XCTAssertTrue(viewModel.canRefreshUsage)

        viewModel.refreshUsage(force: true)
        await waitForExpectations()

        let refreshUsageCallCount = await service.recordedRefreshUsageCallCount()
        XCTAssertEqual(refreshUsageCallCount, 1)
    }

    func testSwitchAccountCancelsWhenConfirmationIsRejected() async throws {
        let service = MenuBarServiceStub(
            dashboardSnapshot: makeDashboardSnapshotWithUsageCache(),
            switchResult: ManagedAccount(
                recordKey: "user-2::acct-2",
                email: "two@example.com",
                plan: "pro",
                chatgptUserID: "user-2",
                chatgptAccountID: "acct-2",
                authMode: "chatgpt"
            )
        )
        let scheduler = ManualUsageRefreshScheduler()
        let switchConfirmer = SwitchConfirmationStub(result: false)
        let viewModel = MenuBarViewModel(
            service: service,
            switchConfirmer: switchConfirmer,
            autoRefreshInterval: 300,
            scheduler: scheduler
        )

        viewModel.switchAccount(recordKey: "user-2::acct-2")
        await waitForExpectations()

        let switchCallCount = await service.recordedSwitchAccountCallCount()
        XCTAssertEqual(switchConfirmer.callCount, 1)
        XCTAssertEqual(switchCallCount, 0)
        XCTAssertNil(viewModel.pendingRecordKey)
        XCTAssertNil(viewModel.notice)
    }

    func testSwitchAccountAfterConfirmationShowsSuccessNotice() async throws {
        let service = MenuBarServiceStub(
            dashboardSnapshot: makeDashboardSnapshotWithUsageCache(),
            switchResult: ManagedAccount(
                recordKey: "user-2::acct-2",
                email: "two@example.com",
                plan: "pro",
                chatgptUserID: "user-2",
                chatgptAccountID: "acct-2",
                authMode: "chatgpt"
            )
        )
        let scheduler = ManualUsageRefreshScheduler()
        let switchConfirmer = SwitchConfirmationStub(result: true)
        let viewModel = MenuBarViewModel(
            service: service,
            switchConfirmer: switchConfirmer,
            autoRefreshInterval: 300,
            scheduler: scheduler
        )

        viewModel.switchAccount(recordKey: "user-2::acct-2")
        await waitForExpectations()

        let switchCallCount = await service.recordedSwitchAccountCallCount()
        let switchedRecordKey = await service.recordedSwitchedRecordKey()
        XCTAssertEqual(switchConfirmer.callCount, 1)
        XCTAssertEqual(switchCallCount, 1)
        XCTAssertEqual(switchedRecordKey, "user-2::acct-2")
        XCTAssertEqual(viewModel.notice, .success("已切换到：two@example.com"))
        XCTAssertNil(viewModel.pendingRecordKey)
    }

    func testThemeModeDefaultsToLightWhenNoPreferenceExists() {
        let service = MenuBarServiceStub()
        let scheduler = ManualUsageRefreshScheduler()
        let themeStore = ThemePreferenceStoreStub(initialMode: nil)
        let viewModel = MenuBarViewModel(
            service: service,
            themePreferenceStore: themeStore,
            autoRefreshInterval: 300,
            scheduler: scheduler
        )

        XCTAssertEqual(viewModel.themeMode, .light)
        XCTAssertEqual(viewModel.themeButtonSystemName, "sun.max.fill")
    }

    func testThemeModeLoadsStoredPreference() {
        for mode in PanelThemeMode.allCases {
            let service = MenuBarServiceStub()
            let scheduler = ManualUsageRefreshScheduler()
            let themeStore = ThemePreferenceStoreStub(initialMode: mode)
            let viewModel = MenuBarViewModel(
                service: service,
                themePreferenceStore: themeStore,
                autoRefreshInterval: 300,
                scheduler: scheduler
            )

            XCTAssertEqual(viewModel.themeMode, mode)
        }
    }

    func testCycleThemeModeRotatesAndPersists() {
        let service = MenuBarServiceStub()
        let scheduler = ManualUsageRefreshScheduler()
        let themeStore = ThemePreferenceStoreStub(initialMode: .light)
        let viewModel = MenuBarViewModel(
            service: service,
            themePreferenceStore: themeStore,
            autoRefreshInterval: 300,
            scheduler: scheduler
        )

        viewModel.cycleThemeMode()
        XCTAssertEqual(viewModel.themeMode, .dark)
        XCTAssertEqual(themeStore.savedModes, [.dark])

        viewModel.cycleThemeMode()
        XCTAssertEqual(viewModel.themeMode, .system)
        XCTAssertEqual(themeStore.savedModes, [.dark, .system])

        viewModel.cycleThemeMode()
        XCTAssertEqual(viewModel.themeMode, .light)
        XCTAssertEqual(themeStore.savedModes, [.dark, .system, .light])
    }

    func testPanelThemeModeMappings() {
        XCTAssertEqual(PanelThemeMode.light.iconSystemName, "sun.max.fill")
        XCTAssertEqual(PanelThemeMode.dark.iconSystemName, "moon.fill")
        XCTAssertEqual(PanelThemeMode.system.iconSystemName, "circle.lefthalf.filled")
        XCTAssertEqual(PanelThemeMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(PanelThemeMode.dark.nsAppearance?.name, .darkAqua)
        XCTAssertNil(PanelThemeMode.system.nsAppearance)
        XCTAssertEqual(PanelThemeMode.dark.buttonLabel, "主题模式：深色，点击切换到跟随系统")
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

    private func makeDashboardSnapshotWithUsageCache() -> DashboardSnapshot {
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
                ManagedAccount(
                    recordKey: "user-2::acct-2",
                    email: "two@example.com",
                    plan: "pro",
                    chatgptUserID: "user-2",
                    chatgptAccountID: "acct-2",
                    authMode: "chatgpt"
                ),
            ],
            activeRecordKey: "user-1::acct-1",
            liveRecordKey: "user-1::acct-1",
            unmanagedLiveEmail: nil,
            usageCache: [
                "user-1::acct-1": UsageSummary(
                    fiveHour: UsageWindow(remainingPercent: 80, windowMinutes: 300, resetAt: nil),
                    weekly: UsageWindow(remainingPercent: 90, windowMinutes: 10_080, resetAt: nil),
                    fetchedAt: Date(timeIntervalSince1970: 1_700_000_100)
                ),
                "user-2::acct-2": UsageSummary(
                    fiveHour: UsageWindow(remainingPercent: 60, windowMinutes: 300, resetAt: nil),
                    weekly: UsageWindow(remainingPercent: 70, windowMinutes: 10_080, resetAt: nil),
                    fetchedAt: Date(timeIntervalSince1970: 1_700_001_100)
                ),
            ],
            liveErrorMessage: nil
        )
    }
}

private actor MenuBarServiceStub: MenuBarServicing {
    private let dashboardSnapshot: DashboardSnapshot
    private let refreshUsageResult: UsageRefreshResult
    private let loginResult: ManagedAccount
    private let switchResult: ManagedAccount
    private let refreshDelay: UInt64
    private let loginDelay: UInt64
    private let switchDelay: UInt64

    private(set) var loadDashboardCallCount = 0
    private(set) var refreshUsageCallCount = 0
    private(set) var switchAccountCallCount = 0
    private(set) var switchedRecordKey: String?

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
        loginResult: ManagedAccount = ManagedAccount(
            recordKey: "user-1::acct-1",
            email: "one@example.com",
            plan: "team",
            chatgptUserID: "user-1",
            chatgptAccountID: "acct-1",
            authMode: "chatgpt"
        ),
        switchResult: ManagedAccount = ManagedAccount(
            recordKey: "user-1::acct-1",
            email: "one@example.com",
            plan: "team",
            chatgptUserID: "user-1",
            chatgptAccountID: "acct-1",
            authMode: "chatgpt"
        ),
        refreshDelay: UInt64 = 0,
        loginDelay: UInt64 = 0,
        switchDelay: UInt64 = 0
    ) {
        self.dashboardSnapshot = dashboardSnapshot
        self.refreshUsageResult = refreshUsageResult
        self.loginResult = loginResult
        self.switchResult = switchResult
        self.refreshDelay = refreshDelay
        self.loginDelay = loginDelay
        self.switchDelay = switchDelay
    }

    func loadDashboard() async throws -> DashboardSnapshot {
        loadDashboardCallCount += 1
        return dashboardSnapshot
    }

    func captureCurrentAccount() async throws -> ManagedAccount {
        throw CodexSwitchError("unused")
    }

    func loginNewAccount() async throws -> ManagedAccount {
        if loginDelay > 0 {
            try await Task.sleep(nanoseconds: loginDelay)
        }
        return loginResult
    }

    func switchAccount(recordKey: String) async throws -> ManagedAccount {
        switchAccountCallCount += 1
        switchedRecordKey = recordKey
        if switchDelay > 0 {
            try await Task.sleep(nanoseconds: switchDelay)
        }
        return switchResult
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

    func recordedLoadDashboardCallCount() -> Int {
        loadDashboardCallCount
    }

    func recordedRefreshUsageCallCount() -> Int {
        refreshUsageCallCount
    }

    func recordedSwitchAccountCallCount() -> Int {
        switchAccountCallCount
    }

    func recordedSwitchedRecordKey() -> String? {
        switchedRecordKey
    }
}

private final class SwitchConfirmationStub: AccountSwitchConfirming {
    private let result: Bool
    private(set) var callCount = 0

    init(result: Bool) {
        self.result = result
    }

    @MainActor
    func confirmSwitchAccount() -> Bool {
        callCount += 1
        return result
    }
}

private final class ManualUsageRefreshScheduler: UsageRefreshScheduling {
    private struct ScheduledAction {
        let action: @MainActor () -> Void
        var isCancelled: Bool
    }

    private var actions: [ScheduledAction] = []

    @MainActor
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyCancellable {
        let index = actions.count
        actions.append(ScheduledAction(action: action, isCancelled: false))
        return AnyCancellable { [weak self] in
            self?.cancelAction(at: index)
        }
    }

    @MainActor
    func fire() {
        guard let lastIndex = actions.indices.last else { return }
        let scheduledAction = actions[lastIndex]
        guard !scheduledAction.isCancelled else { return }
        scheduledAction.action()
    }

    @MainActor
    func fire(at index: Int) {
        guard actions.indices.contains(index) else { return }
        let scheduledAction = actions[index]
        guard !scheduledAction.isCancelled else { return }
        scheduledAction.action()
    }

    @MainActor
    func recordedScheduleCount() -> Int {
        actions.count
    }

    @MainActor
    private func cancelAction(at index: Int) {
        guard actions.indices.contains(index) else { return }
        actions[index].isCancelled = true
    }
}

private final class ThemePreferenceStoreStub: ThemePreferenceStoring {
    private let initialMode: PanelThemeMode?
    private(set) var savedModes: [PanelThemeMode] = []

    init(initialMode: PanelThemeMode?) {
        self.initialMode = initialMode
    }

    func loadThemeMode() -> PanelThemeMode? {
        initialMode
    }

    func saveThemeMode(_ mode: PanelThemeMode) {
        savedModes.append(mode)
    }
}
