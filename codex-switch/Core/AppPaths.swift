import Foundation

public struct AppPaths: Equatable, Sendable {
    public let codexHome: URL
    public let switcherHome: URL

    public init(codexHome: URL, switcherHome: URL) {
        self.codexHome = codexHome
        self.switcherHome = switcherHome
    }

    public static func appSupportDefault(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> AppPaths {
        let codexHome: URL
        if let override = environment["CODEX_HOME"], !override.isEmpty {
            codexHome = URL(fileURLWithPath: NSString(string: override).expandingTildeInPath, isDirectory: true)
        } else {
            codexHome = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        }

        let appSupportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let folderName = (bundleIdentifier == nil || bundleIdentifier == "org.swift.swiftpm.package")
            ? "CodexSwitch"
            : bundleIdentifier!

        return AppPaths(
            codexHome: codexHome,
            switcherHome: appSupportBase.appendingPathComponent(folderName, isDirectory: true)
        )
    }

    public var liveAuthURL: URL {
        codexHome.appendingPathComponent("auth.json", isDirectory: false)
    }

    public var registryURL: URL {
        switcherHome.appendingPathComponent("registry.json", isDirectory: false)
    }

    public var accountsDirectoryURL: URL {
        switcherHome.appendingPathComponent("accounts", isDirectory: true)
    }

    public var backupsDirectoryURL: URL {
        switcherHome.appendingPathComponent("backups", isDirectory: true)
    }

    public var usageCacheURL: URL {
        switcherHome.appendingPathComponent("usage-cache.json", isDirectory: false)
    }

    public func snapshotURL(for recordKey: String) -> URL {
        accountsDirectoryURL.appendingPathComponent("\(Base64URL.encode(recordKey)).auth.json", isDirectory: false)
    }
}
