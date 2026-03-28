import Foundation

public actor CodexSwitchService {
    private let paths: AppPaths
    private let store: AccountStore
    private let authParser: AuthParser
    private let usageService: UsageService
    private let loginCoordinator: LoginCoordinator

    public init(
        paths: AppPaths = AppPaths.appSupportDefault(),
        store: AccountStore = AccountStore(),
        authParser: AuthParser = AuthParser(),
        usageService: UsageService = UsageService(),
        loginCoordinator: LoginCoordinator = LoginCoordinator()
    ) {
        self.paths = paths
        self.store = store
        self.authParser = authParser
        self.usageService = usageService
        self.loginCoordinator = loginCoordinator
    }

    public func loadDashboard() throws -> DashboardSnapshot {
        var registry = try store.loadRegistry(at: paths)
        var liveSync: LiveSyncResult?
        var liveErrorMessage: String?

        do {
            let sync = try syncLiveAuth(registry: &registry)
            if sync.changed {
                try store.saveRegistry(registry, at: paths)
            }
            liveSync = sync
        } catch let error as CodexSwitchError {
            liveErrorMessage = error.message
        }

        let usageCache = (try? store.loadUsageCache(at: paths)) ?? [:]
        let unmanagedLiveEmail = liveSync.flatMap { $0.managed ? nil : $0.liveInfo.email }

        return DashboardSnapshot(
            accounts: sortedAccounts(registry.accounts),
            activeRecordKey: registry.activeRecordKey,
            liveRecordKey: liveSync?.liveInfo.recordKey,
            unmanagedLiveEmail: unmanagedLiveEmail,
            usageCache: usageCache,
            liveErrorMessage: liveErrorMessage
        )
    }

    public func captureCurrentAccount() throws -> ManagedAccount {
        var registry = try store.loadRegistry(at: paths)
        let (liveInfo, liveData) = try authParser.parseAuthFile(at: paths.liveAuthURL)
        let account = upsertAccount(with: liveInfo, in: &registry)
        try store.saveSnapshot(liveData, for: liveInfo.recordKey, at: paths)
        registry.activeRecordKey = liveInfo.recordKey
        try store.saveRegistry(registry, at: paths)
        return account
    }

    public func loginNewAccount() async throws -> ManagedAccount {
        try await loginCoordinator.login()
        return try captureCurrentAccount()
    }

    public func switchAccount(recordKey: String) throws -> ManagedAccount {
        var (registry, _) = try loadAndSyncRequiredRegistry()

        guard !registry.accounts.isEmpty else {
            throw CodexSwitchError("当前没有任何已管理账号，请先收录当前账号或登录新账号。")
        }
        guard let account = registry.accounts.first(where: { $0.recordKey == recordKey }) else {
            throw CodexSwitchError("未找到目标账号。")
        }

        let snapshotData = try store.loadSnapshot(for: recordKey, at: paths)
        let liveURL = paths.liveAuthURL
        let liveData = try? Data(contentsOf: liveURL)

        if let liveData, liveData != snapshotData {
            try store.createBackup(from: liveData, at: paths)
        }

        try store.ensureDirectories(at: paths)
        try snapshotData.write(to: liveURL, options: .atomic)
        registry.activeRecordKey = recordKey
        try store.saveRegistry(registry, at: paths)
        return account
    }

    public func removeAccount(recordKey: String) throws -> ManagedAccount {
        var (registry, _) = try loadAndSyncRequiredRegistry()

        guard !registry.accounts.isEmpty else {
            throw CodexSwitchError("当前没有任何已管理账号可删除。")
        }
        guard let index = registry.accounts.firstIndex(where: { $0.recordKey == recordKey }) else {
            throw CodexSwitchError("待删除账号不存在。")
        }

        let removed = registry.accounts.remove(at: index)
        store.deleteSnapshot(for: recordKey, at: paths)
        if registry.activeRecordKey == recordKey {
            registry.activeRecordKey = nil
        }
        try store.saveRegistry(registry, at: paths)
        return removed
    }

    public func refreshUsage() async throws -> UsageRefreshResult {
        let registry = try store.loadRegistry(at: paths)
        let accounts = sortedAccounts(registry.accounts)
        var cache = (try? store.loadUsageCache(at: paths)) ?? [:]

        guard !accounts.isEmpty else {
            return UsageRefreshResult(usages: cache, failures: [], successCount: 0)
        }

        let liveOverride = loadLiveUsageOverride(registry: registry)
        var refreshed: [String: UsageSummary] = [:]
        var failures: [String] = []

        for batch in accounts.chunked(into: UsageService.maxConcurrentRequests) {
            let workItems = batch.map { account in
                UsageWorkItem(account: account, authData: try? authDataForUsage(account: account, liveOverride: liveOverride))
            }

            let batchResults = await withTaskGroup(of: UsageWorkResult.self, returning: [UsageWorkResult].self) { group in
                for item in workItems {
                    if let authData = item.authData {
                        group.addTask {
                            do {
                                let summary = try await self.usageService.fetchUsage(from: authData)
                                return UsageWorkResult(recordKey: item.account.recordKey, email: item.account.email, summary: summary, error: nil)
                            } catch let error as CodexSwitchError {
                                return UsageWorkResult(recordKey: item.account.recordKey, email: item.account.email, summary: nil, error: error.message)
                            } catch {
                                return UsageWorkResult(recordKey: item.account.recordKey, email: item.account.email, summary: nil, error: error.localizedDescription)
                            }
                        }
                    } else {
                        let message = snapshotFailureMessage(for: item.account)
                        group.addTask {
                            UsageWorkResult(recordKey: item.account.recordKey, email: item.account.email, summary: nil, error: message)
                        }
                    }
                }

                var results: [UsageWorkResult] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            for result in batchResults {
                if let summary = result.summary {
                    refreshed[result.recordKey] = summary
                    cache[result.recordKey] = summary
                } else if let error = result.error {
                    failures.append("\(result.email) 查询失败：\(error)")
                }
            }
        }

        try store.saveUsageCache(cache, at: paths)
        return UsageRefreshResult(usages: cache, failures: failures, successCount: refreshed.count)
    }

    private func loadAndSyncRequiredRegistry() throws -> (RegistryState, LiveSyncResult) {
        var registry = try store.loadRegistry(at: paths)
        let sync = try syncLiveAuth(registry: &registry)
        if sync.changed {
            try store.saveRegistry(registry, at: paths)
        }
        return (registry, sync)
    }

    private func syncLiveAuth(registry: inout RegistryState) throws -> LiveSyncResult {
        let (liveInfo, liveData) = try authParser.parseAuthFile(at: paths.liveAuthURL)
        let managedIndex = registry.accounts.firstIndex(where: { $0.recordKey == liveInfo.recordKey })
        var changed = false

        if let managedIndex {
            let account = ManagedAccount(
                recordKey: liveInfo.recordKey,
                email: liveInfo.email,
                plan: liveInfo.plan,
                chatgptUserID: liveInfo.chatgptUserID,
                chatgptAccountID: liveInfo.chatgptAccountID,
                authMode: liveInfo.authMode
            )
            if registry.accounts[managedIndex] != account {
                registry.accounts[managedIndex] = account
                changed = true
            }

            let snapshotURL = paths.snapshotURL(for: liveInfo.recordKey)
            let snapshotData = try? Data(contentsOf: snapshotURL)
            if snapshotData != liveData {
                try store.saveSnapshot(liveData, for: liveInfo.recordKey, at: paths)
                changed = true
            }

            if registry.activeRecordKey != liveInfo.recordKey {
                registry.activeRecordKey = liveInfo.recordKey
                changed = true
            }
        }

        return LiveSyncResult(
            liveInfo: liveInfo,
            liveData: liveData,
            managed: managedIndex != nil,
            changed: changed
        )
    }

    private func loadLiveUsageOverride(registry: RegistryState) -> (recordKey: String, authData: Data)? {
        guard
            let (liveInfo, liveData) = try? authParser.parseAuthFile(at: paths.liveAuthURL),
            registry.accounts.contains(where: { $0.recordKey == liveInfo.recordKey })
        else {
            return nil
        }

        return (liveInfo.recordKey, liveData)
    }

    private func authDataForUsage(account: ManagedAccount, liveOverride: (recordKey: String, authData: Data)?) throws -> Data {
        if let liveOverride, liveOverride.recordKey == account.recordKey {
            return liveOverride.authData
        }
        return try store.loadSnapshot(for: account.recordKey, at: paths)
    }

    private func snapshotFailureMessage(for account: ManagedAccount) -> String {
        "账号快照不存在：\(paths.snapshotURL(for: account.recordKey).path)"
    }

    @discardableResult
    private func upsertAccount(with liveInfo: AuthInfo, in registry: inout RegistryState) -> ManagedAccount {
        let account = ManagedAccount(
            recordKey: liveInfo.recordKey,
            email: liveInfo.email,
            plan: liveInfo.plan,
            chatgptUserID: liveInfo.chatgptUserID,
            chatgptAccountID: liveInfo.chatgptAccountID,
            authMode: liveInfo.authMode
        )

        if let index = registry.accounts.firstIndex(where: { $0.recordKey == liveInfo.recordKey }) {
            registry.accounts[index] = account
        } else {
            registry.accounts.append(account)
        }
        return account
    }

    private func sortedAccounts(_ accounts: [ManagedAccount]) -> [ManagedAccount] {
        accounts.sorted { lhs, rhs in
            if lhs.email == rhs.email {
                return lhs.recordKey < rhs.recordKey
            }
            return lhs.email < rhs.email
        }
    }
}

private struct UsageWorkItem {
    let account: ManagedAccount
    let authData: Data?
}

private struct UsageWorkResult {
    let recordKey: String
    let email: String
    let summary: UsageSummary?
    let error: String?
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else {
            return [self]
        }

        var chunks: [[Element]] = []
        var index = startIndex
        while index < endIndex {
            let end = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
