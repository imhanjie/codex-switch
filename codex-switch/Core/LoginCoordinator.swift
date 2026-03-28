import Foundation

public protocol CodexBinaryLocating: Sendable {
    func locate(environment: [String: String]) throws -> URL
}

public protocol CodexLoginRunning: Sendable {
    func runLogin(executableURL: URL, environment: [String: String]) async throws -> ProcessOutput
}

public struct ProcessOutput: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct DefaultCodexBinaryLocator: CodexBinaryLocating {
    public let fallbackCandidates: [URL]

    public init(
        fallbackCandidates: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
    ) {
        self.fallbackCandidates = fallbackCandidates
    }

    public func locate(environment: [String: String]) throws -> URL {
        var candidates: [URL] = []
        if let path = environment["PATH"] {
            for component in path.split(separator: ":") where !component.isEmpty {
                candidates.append(URL(fileURLWithPath: String(component), isDirectory: true).appendingPathComponent("codex"))
            }
        }
        candidates.append(contentsOf: fallbackCandidates)

        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate.path).inserted {
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw CodexSwitchError("未找到 `codex` 命令，请先安装 Codex CLI。")
    }
}

public struct ProcessCodexLoginRunner: CodexLoginRunning {
    public init() {}

    public func runLogin(executableURL: URL, environment: [String: String]) async throws -> ProcessOutput {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = executableURL
            process.arguments = ["login"]
            process.environment = environment
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(
                    returning: ProcessOutput(
                        exitCode: process.terminationStatus,
                        stdout: String(decoding: stdoutData, as: UTF8.self),
                        stderr: String(decoding: stderrData, as: UTF8.self)
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: CodexSwitchError("无法启动 `codex login`：\(error.localizedDescription)"))
            }
        }
    }
}

public struct LoginCoordinator: Sendable {
    private let environment: [String: String]
    private let locator: CodexBinaryLocating
    private let runner: CodexLoginRunning

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        locator: CodexBinaryLocating = DefaultCodexBinaryLocator(),
        runner: CodexLoginRunning = ProcessCodexLoginRunner()
    ) {
        self.environment = environment
        self.locator = locator
        self.runner = runner
    }

    public func login() async throws {
        let executableURL = try locator.locate(environment: environment)
        let output = try await runner.runLogin(executableURL: executableURL, environment: environment)
        guard output.exitCode == 0 else {
            let details = [output.stderr.trimmingCharacters(in: .whitespacesAndNewlines), output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)]
                .first { !$0.isEmpty }
            if let details {
                throw CodexSwitchError("`codex login` 执行失败：\(details)")
            }
            throw CodexSwitchError("`codex login` 执行失败，退出码：\(output.exitCode)")
        }
    }
}
