import Foundation

public struct AccountStore {
    public static let maxBackups = 5

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func loadRegistry(at paths: AppPaths) throws -> RegistryState {
        do {
            let data = try Data(contentsOf: paths.registryURL)
            return try JSONDecoder().decode(RegistryState.self, from: data)
        } catch is DecodingError {
            throw CodexSwitchError("registry.json 不是合法的 JSON")
        } catch CocoaError.fileReadNoSuchFile {
            return RegistryState()
        } catch {
            throw CodexSwitchError("无法读取 registry.json：\(error.localizedDescription)")
        }
    }

    public func saveRegistry(_ registry: RegistryState, at paths: AppPaths) throws {
        try ensureDirectories(at: paths)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(registry)
        try writeAtomically(data, to: paths.registryURL)
    }

    public func loadUsageCache(at paths: AppPaths) throws -> [String: UsageSummary] {
        do {
            let data = try Data(contentsOf: paths.usageCacheURL)
            let payload = try JSONDecoder().decode(UsageCachePayload.self, from: data)
            return payload.entries
        } catch CocoaError.fileReadNoSuchFile {
            return [:]
        } catch {
            throw CodexSwitchError("usage-cache.json 不是合法的 JSON")
        }
    }

    public func saveUsageCache(_ entries: [String: UsageSummary], at paths: AppPaths) throws {
        try ensureDirectories(at: paths)
        let payload = UsageCachePayload(entries: entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload)
        try writeAtomically(data, to: paths.usageCacheURL)
    }

    public func saveSnapshot(_ data: Data, for recordKey: String, at paths: AppPaths) throws {
        try ensureDirectories(at: paths)
        try writeAtomically(data, to: paths.snapshotURL(for: recordKey))
    }

    public func loadSnapshot(for recordKey: String, at paths: AppPaths) throws -> Data {
        do {
            return try Data(contentsOf: paths.snapshotURL(for: recordKey))
        } catch CocoaError.fileReadNoSuchFile {
            throw CodexSwitchError("账号快照不存在：\(paths.snapshotURL(for: recordKey).path)")
        } catch {
            throw CodexSwitchError("无法读取账号快照：\(error.localizedDescription)")
        }
    }

    public func deleteSnapshot(for recordKey: String, at paths: AppPaths) {
        try? fileManager.removeItem(at: paths.snapshotURL(for: recordKey))
    }

    @discardableResult
    public func createBackup(from liveData: Data, at paths: AppPaths) throws -> URL {
        try ensureDirectories(at: paths)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSSSSS"
        let backupURL = paths.backupsDirectoryURL.appendingPathComponent(
            "auth.json.bak.\(formatter.string(from: Date()))",
            isDirectory: false
        )
        try writeAtomically(liveData, to: backupURL)
        try pruneBackups(at: paths)
        return backupURL
    }

    public func ensureDirectories(at paths: AppPaths) throws {
        try fileManager.createDirectory(at: paths.switcherHome, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.accountsDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: paths.backupsDirectoryURL, withIntermediateDirectories: true)
    }

    private func pruneBackups(at paths: AppPaths) throws {
        let backups = try fileManager.contentsOfDirectory(
            at: paths.backupsDirectoryURL,
            includingPropertiesForKeys: nil
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        let overflow = backups.count - Self.maxBackups
        guard overflow > 0 else {
            return
        }

        for backup in backups.prefix(overflow) {
            try? fileManager.removeItem(at: backup)
        }
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        if let parent = url.deletingLastPathComponent() as URL? {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }
}

private struct UsageCachePayload: Codable {
    let entries: [String: UsageSummary]
}
