import AppKit
import Combine
import Foundation
#if SWIFT_PACKAGE
import CodexSwitchCore
#endif

enum PanelThemeMode: String, CaseIterable {
    case light
    case dark
    case system

    var next: PanelThemeMode {
        switch self {
        case .light:
            return .dark
        case .dark:
            return .system
        case .system:
            return .light
        }
    }

    var displayName: String {
        switch self {
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        case .system:
            return "跟随系统"
        }
    }

    var iconSystemName: String {
        switch self {
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        case .system:
            return "circle.lefthalf.filled"
        }
    }

    var buttonLabel: String {
        "主题模式：\(displayName)，点击切换到\(next.displayName)"
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .system:
            return nil
        }
    }
}

protocol ThemePreferenceStoring {
    func loadThemeMode() -> PanelThemeMode?
    func saveThemeMode(_ mode: PanelThemeMode)
}

struct UserDefaultsThemePreferenceStore: ThemePreferenceStoring {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "panel_theme_mode") {
        self.defaults = defaults
        self.key = key
    }

    func loadThemeMode() -> PanelThemeMode? {
        defaults.string(forKey: key).flatMap(PanelThemeMode.init(rawValue:))
    }

    func saveThemeMode(_ mode: PanelThemeMode) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

protocol MenuBarServicing: Sendable {
    func loadDashboard() async throws -> DashboardSnapshot
    func captureCurrentAccount() async throws -> ManagedAccount
    func loginNewAccount() async throws -> ManagedAccount
    func switchAccount(recordKey: String) async throws -> ManagedAccount
    func removeAccount(recordKey: String) async throws -> ManagedAccount
    func refreshUsage() async throws -> UsageRefreshResult
}

protocol UsageRefreshScheduling {
    @MainActor
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyCancellable
}

protocol AccountSwitchConfirming {
    @MainActor
    func confirmSwitchAccount() -> Bool
}

struct DefaultAccountSwitchConfirmer: AccountSwitchConfirming {
    @MainActor
    func confirmSwitchAccount() -> Bool {
        let alert = NSAlert()
        alert.messageText = "确认切换账号"
        alert.informativeText = "切换后请自行重启 Codex App、Codex CLI、Codex IDE 插件"
        alert.alertStyle = .warning
        alert.icon = NSApp.applicationIconImage
        alert.addButton(withTitle: "切换")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

struct DefaultMenuBarService: MenuBarServicing {
    private let service: CodexSwitchService

    init(service: CodexSwitchService = CodexSwitchService()) {
        self.service = service
    }

    func loadDashboard() async throws -> DashboardSnapshot {
        try await service.loadDashboard()
    }

    func captureCurrentAccount() async throws -> ManagedAccount {
        try await service.captureCurrentAccount()
    }

    func loginNewAccount() async throws -> ManagedAccount {
        try await service.loginNewAccount()
    }

    func switchAccount(recordKey: String) async throws -> ManagedAccount {
        try await service.switchAccount(recordKey: recordKey)
    }

    func removeAccount(recordKey: String) async throws -> ManagedAccount {
        try await service.removeAccount(recordKey: recordKey)
    }

    func refreshUsage() async throws -> UsageRefreshResult {
        try await service.refreshUsage()
    }
}

struct TimerUsageRefreshScheduler: UsageRefreshScheduling {
    @MainActor
    func schedule(every interval: TimeInterval, action: @escaping @MainActor () -> Void) -> AnyCancellable {
        Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                action()
            }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    nonisolated static let defaultAutoRefreshInterval: TimeInterval = 300

    @Published private(set) var accounts: [AccountDisplayItem] = []
    @Published private(set) var themeMode: PanelThemeMode
    @Published private(set) var unmanagedLiveEmail: String?
    @Published private(set) var notice: PanelNotice?
    @Published private(set) var isRefreshingUsage = false
    @Published private(set) var isRunningLogin = false
    @Published private(set) var pendingRecordKey: String?
    @Published private(set) var isCapturing = false
    @Published private(set) var isRemoving = false

    private let service: any MenuBarServicing
    private let switchConfirmer: any AccountSwitchConfirming
    private let themePreferenceStore: any ThemePreferenceStoring
    private let autoRefreshInterval: TimeInterval
    private let scheduler: any UsageRefreshScheduling
    private var sourceAccounts: [ManagedAccount] = []
    private var usageByRecordKey: [String: UsageSummary] = [:]
    private var activeRecordKey: String?
    private var duplicateEmailCounts: [String: Int] = [:]
    private var autoRefreshCancellable: AnyCancellable?

    init(
        service: any MenuBarServicing = DefaultMenuBarService(),
        switchConfirmer: any AccountSwitchConfirming = DefaultAccountSwitchConfirmer(),
        themePreferenceStore: any ThemePreferenceStoring = UserDefaultsThemePreferenceStore(),
        autoRefreshInterval: TimeInterval = defaultAutoRefreshInterval,
        scheduler: any UsageRefreshScheduling = TimerUsageRefreshScheduler()
    ) {
        self.service = service
        self.switchConfirmer = switchConfirmer
        self.themePreferenceStore = themePreferenceStore
        self.themeMode = themePreferenceStore.loadThemeMode() ?? .light
        self.autoRefreshInterval = autoRefreshInterval
        self.scheduler = scheduler
        scheduleAutoRefresh()
    }

    var canRefreshUsage: Bool {
        !isRefreshingUsage
    }

    var canCaptureCurrentAccount: Bool {
        !isCapturing
    }

    var canLoginNewAccount: Bool {
        !isRunningLogin
    }

    var canRemoveAccount: Bool {
        !isRemoving
    }

    var canSwitchAccounts: Bool {
        pendingRecordKey == nil
    }

    var lastUsageRefreshText: String {
        UsageDisplayFormatter.lastRefreshText(for: latestUsageRefreshDate)
    }

    var themeButtonSystemName: String {
        themeMode.iconSystemName
    }

    var themeButtonAccessibilityLabel: String {
        themeMode.buttonLabel
    }

    func loadPanel() {
        Task { [weak self] in
            await self?.reloadDashboard(preserveNotice: false)
        }
    }

    func refreshUsage(force: Bool) {
        refreshUsage(force: force, showSuccessNotice: force)
    }

    func refreshUsage(force: Bool, showSuccessNotice: Bool) {
        if force {
            scheduleAutoRefresh()
        }
        guard force || !isRefreshingUsage else { return }
        Task { [weak self] in
            await self?.performUsageRefresh(showSuccessNotice: showSuccessNotice)
        }
    }

    func captureCurrentAccount() {
        guard canCaptureCurrentAccount else { return }
        isCapturing = true
        Task { [weak self] in
            guard let self else { return }
            defer { self.isCapturing = false }

            do {
                let account = try await self.service.captureCurrentAccount()
                self.notice = PanelNotice.success("已收录账号：\(account.email)")
                await self.reloadDashboard(preserveNotice: true)
            } catch let error as CodexSwitchError {
                self.notice = PanelNotice.error(error.message)
            } catch {
                self.notice = PanelNotice.error(error.localizedDescription)
            }
        }
    }

    func loginNewAccount() {
        guard canLoginNewAccount else { return }
        isRunningLogin = true
        notice = PanelNotice.info("正在打开 Codex 登录流程...")

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRunningLogin = false }

            do {
                let account = try await self.service.loginNewAccount()
                self.notice = PanelNotice.success("登录并收录成功：\(account.email)")
                await self.reloadDashboard(preserveNotice: true)
            } catch let error as CodexSwitchError {
                self.notice = PanelNotice.error(error.message)
            } catch {
                self.notice = PanelNotice.error(error.localizedDescription)
            }
        }
    }

    func switchAccount(recordKey: String) {
        guard canSwitchAccounts else { return }
        guard switchConfirmer.confirmSwitchAccount() else { return }
        pendingRecordKey = recordKey

        Task { [weak self] in
            guard let self else { return }
            defer { self.pendingRecordKey = nil }

            do {
                let account = try await self.service.switchAccount(recordKey: recordKey)
                self.notice = PanelNotice.success("已切换到：\(account.email)")
                await self.reloadDashboard(preserveNotice: true)
            } catch let error as CodexSwitchError {
                self.notice = PanelNotice.error(error.message)
            } catch {
                self.notice = PanelNotice.error(error.localizedDescription)
            }
        }
    }

    func removeAccount(recordKey: String) {
        guard canRemoveAccount else { return }
        isRemoving = true

        Task { [weak self] in
            guard let self else { return }
            defer { self.isRemoving = false }

            do {
                let account = try await self.service.removeAccount(recordKey: recordKey)
                self.notice = PanelNotice.success("已删除账号：\(account.email)")
                await self.reloadDashboard(preserveNotice: true)
            } catch let error as CodexSwitchError {
                self.notice = PanelNotice.error(error.message)
            } catch {
                self.notice = PanelNotice.error(error.localizedDescription)
            }
        }
    }

    func cycleThemeMode() {
        let nextMode = themeMode.next
        themeMode = nextMode
        themePreferenceStore.saveThemeMode(nextMode)
    }

    private func reloadDashboard(preserveNotice: Bool) async {
        do {
            let snapshot = try await service.loadDashboard()
            apply(snapshot: snapshot, preserveNotice: preserveNotice)
        } catch let error as CodexSwitchError {
            notice = PanelNotice.error(error.message)
        } catch {
            notice = PanelNotice.error(error.localizedDescription)
        }
    }

    private func apply(snapshot: DashboardSnapshot, preserveNotice: Bool) {
        sourceAccounts = snapshot.accounts
        usageByRecordKey = snapshot.usageCache
        activeRecordKey = snapshot.activeRecordKey
        unmanagedLiveEmail = snapshot.unmanagedLiveEmail
        duplicateEmailCounts = Dictionary(grouping: sourceAccounts, by: \.email).mapValues(\.count)
        rebuildAccounts()

        if !preserveNotice {
            notice = snapshot.liveErrorMessage.map(PanelNotice.error)
        } else if notice == nil, let liveErrorMessage = snapshot.liveErrorMessage {
            notice = PanelNotice.error(liveErrorMessage)
        }
    }

    private func performUsageRefresh(showSuccessNotice: Bool) async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }

        do {
            let result = try await service.refreshUsage()
            usageByRecordKey = result.usages
            rebuildAccounts()

            if !result.failures.isEmpty {
                notice = PanelNotice.error(result.failures.joined(separator: "\n"))
            } else if showSuccessNotice {
                notice = PanelNotice.success("额度已刷新")
            }
        } catch let error as CodexSwitchError {
            notice = PanelNotice.error(error.message)
        } catch {
            notice = PanelNotice.error(error.localizedDescription)
        }
    }

    private func rebuildAccounts() {
        let activeRecordKey = activeRecordKey
        accounts = sourceAccounts
            .sorted { lhs, rhs in
                if lhs.recordKey == activeRecordKey { return true }
                if rhs.recordKey == activeRecordKey { return false }
                if lhs.email == rhs.email { return lhs.recordKey < rhs.recordKey }
                return lhs.email < rhs.email
            }
            .map { account in
                let needsMetadata = (duplicateEmailCounts[account.email] ?? 0) > 1 || account.plan != nil
                let metadataText: String?
                if needsMetadata {
                    var parts: [String] = []
                    if let plan = account.plan, !plan.isEmpty {
                        parts.append(plan.uppercased())
                    }
                    parts.append(account.shortKey)
                    metadataText = parts.joined(separator: " · ")
                } else {
                    metadataText = nil
                }

                return AccountDisplayItem(
                    account: account,
                    usage: usageByRecordKey[account.recordKey],
                    metadataText: metadataText,
                    isCurrent: account.recordKey == activeRecordKey,
                    isPending: account.recordKey == pendingRecordKey
                )
            }
    }

    private var latestUsageRefreshDate: Date? {
        usageByRecordKey.values.map(\.fetchedAt).max()
    }

    private func scheduleAutoRefresh() {
        autoRefreshCancellable?.cancel()
        autoRefreshCancellable = nil

        guard autoRefreshInterval > 0 else { return }
        autoRefreshCancellable = scheduler.schedule(every: autoRefreshInterval) { [weak self] in
            self?.refreshUsage(force: false, showSuccessNotice: false)
        }
    }
}

struct AccountDisplayItem: Identifiable {
    let account: ManagedAccount
    let usage: UsageSummary?
    let metadataText: String?
    let isCurrent: Bool
    let isPending: Bool

    var id: String {
        account.recordKey
    }
}

struct PanelNotice: Equatable {
    enum Style: Equatable {
        case info
        case success
        case error
    }

    let text: String
    let style: Style

    static func info(_ text: String) -> PanelNotice {
        PanelNotice(text: text, style: .info)
    }

    static func success(_ text: String) -> PanelNotice {
        PanelNotice(text: text, style: .success)
    }

    static func error(_ text: String) -> PanelNotice {
        PanelNotice(text: text, style: .error)
    }
}
