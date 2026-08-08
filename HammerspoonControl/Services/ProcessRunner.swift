import Foundation

public struct ProcessResult: Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var isSuccess: Bool {
        exitCode == 0
    }
}

public struct CommandDescriptor: Equatable {
    public let executablePath: String
    public let arguments: [String]
    public let timeoutSeconds: TimeInterval

    public init(executablePath: String, arguments: [String], timeoutSeconds: TimeInterval = 5.0) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }
}

public typealias ProcessLauncher = (CommandDescriptor) throws -> ProcessResult

public struct RuntimeSentinelInfo: Equatable {
    public let version: Int
    public let isReady: Bool
    public let generation: String

    public init(version: Int, isReady: Bool, generation: String) {
        self.version = version
        self.isReady = isReady
        self.generation = generation
    }
}

public protocol ProcessRunnerProtocol {
    var hsExecutablePath: String { get }
    var nightlightExecutablePath: String { get }
    var hammerspoonAppPath: String { get }

    func runHsReload() throws -> ProcessResult
    func queryRuntimeSentinel() -> (result: ProcessResult, sentinel: RuntimeSentinelInfo?)
    func queryRuntimeHealth() -> ProcessResult
    func reloadAndVerifyHealth(previousGeneration: String?, timeoutSeconds: TimeInterval) -> (reloadResult: ProcessResult, healthResult: ProcessResult, freshGeneration: String?)
    func checkDependencies() -> [SystemDependency]
}

extension ProcessRunnerProtocol {
    public func reloadAndVerifyHealth(previousGeneration: String? = nil, timeoutSeconds: TimeInterval = 5.0) -> (reloadResult: ProcessResult, healthResult: ProcessResult, freshGeneration: String?) {
        return reloadAndVerifyHealth(previousGeneration: previousGeneration, timeoutSeconds: timeoutSeconds)
    }
}

public final class ProcessRunner: ProcessRunnerProtocol {
    private let customHsPath: String?
    private let customNightlightPath: String?
    private let customAppPath: String?
    private let launcher: ProcessLauncher?

    public init(
        customHsPath: String? = nil,
        customNightlightPath: String? = nil,
        customAppPath: String? = nil,
        launcher: ProcessLauncher? = nil
    ) {
        self.customHsPath = customHsPath
        self.customNightlightPath = customNightlightPath
        self.customAppPath = customAppPath
        self.launcher = launcher
    }

    public var hsExecutablePath: String {
        if let custom = customHsPath { return custom }
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["HAMMERSPOON_CONTROL_HS_PATH"], !override.isEmpty {
            return override
        }
        #endif
        return "/opt/homebrew/bin/hs"
    }

    public var nightlightExecutablePath: String {
        if let custom = customNightlightPath { return custom }
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["HAMMERSPOON_CONTROL_NIGHTLIGHT_PATH"], !override.isEmpty {
            return override
        }
        #endif
        return "/opt/homebrew/bin/nightlight"
    }

    public var hammerspoonAppPath: String {
        if let custom = customAppPath { return custom }
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["HAMMERSPOON_CONTROL_APP_PATH"], !override.isEmpty {
            return override
        }
        #endif
        return "/Applications/Hammerspoon.app"
    }

    public func checkDependencies() -> [SystemDependency] {
        let fm = FileManager.default
        let hsPresent = fm.fileExists(atPath: hsExecutablePath)
        let nightlightPresent = fm.fileExists(atPath: nightlightExecutablePath)
        let appPresent = fm.fileExists(atPath: hammerspoonAppPath)

        return [
            SystemDependency(id: "hammerspoon", displayName: "Hammerspoon App", expectedPath: hammerspoonAppPath, isPresent: appPresent),
            SystemDependency(id: "hs", displayName: "Hammerspoon CLI (hs)", expectedPath: hsExecutablePath, isPresent: hsPresent),
            SystemDependency(id: "nightlight", displayName: "nightlight CLI", expectedPath: nightlightExecutablePath, isPresent: nightlightPresent)
        ]
    }

    public func runHsReload() throws -> ProcessResult {
        let command = CommandDescriptor(
            executablePath: hsExecutablePath,
            arguments: ["-c", "hs.reload()"],
            timeoutSeconds: 5.0
        )
        return try executeCommand(command)
    }

    public func queryRuntimeSentinel() -> (result: ProcessResult, sentinel: RuntimeSentinelInfo?) {
        let sentinelCmd = "if _G.hsControlSentinel and type(_G.hsControlSentinel) == \"table\" then return string.format(\"V=%s;READY=%s;GEN=%s\", tostring(_G.hsControlSentinel.version or \"\"), tostring(_G.hsControlSentinel.ready), tostring(_G.hsControlSentinel.generation or \"\")) else return \"NOT_PRESENT\" end"
        let command = CommandDescriptor(
            executablePath: hsExecutablePath,
            arguments: ["-c", sentinelCmd],
            timeoutSeconds: 5.0
        )
        do {
            let res = try executeCommand(command)
            if res.isSuccess {
                return (res, ProcessRunner.parseSentinel(res.stdout))
            }
            return (res, nil)
        } catch {
            return (ProcessResult(exitCode: 1, stdout: "", stderr: "Sentinel query failed: \(error.localizedDescription)"), nil)
        }
    }

    /// Hammerspoon prefixes command output with lines like `-- Loading extension: settings`
    /// whenever a Lua module is autoloaded, so the sentinel record is not guaranteed to be
    /// the whole of stdout. Scan the lines for the record rather than parsing the buffer
    /// wholesale, which would otherwise fold the noise into the version field and report a
    /// misleading "Unsupported sentinel version -1".
    static func parseSentinel(_ stdout: String) -> RuntimeSentinelInfo? {
        let lines = stdout
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            if line == "NOT_PRESENT" { return nil }

            var dict: [String: String] = [:]
            for part in line.components(separatedBy: ";") {
                let kv = part.components(separatedBy: "=")
                if kv.count == 2 {
                    dict[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1]
                }
            }

            guard let versionText = dict["V"], let version = Int(versionText), dict["READY"] != nil else {
                continue
            }
            return RuntimeSentinelInfo(
                version: version,
                isReady: dict["READY"] == "true",
                generation: dict["GEN"] ?? ""
            )
        }
        return nil
    }

    public func queryRuntimeHealth() -> ProcessResult {
        let (res, sentinel) = queryRuntimeSentinel()
        if !res.isSuccess {
            return res
        }
        guard let s = sentinel else {
            return ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: "Sentinel missing (_G.hsControlSentinel is nil)")
        }
        guard s.version == 1 else {
            return ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: "Unsupported sentinel version \(s.version) (expected 1)")
        }
        guard s.isReady else {
            return ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: "Sentinel ready flag is false")
        }
        return ProcessResult(exitCode: 0, stdout: "HEALTHY_V1", stderr: "")
    }

    public func reloadAndVerifyHealth(previousGeneration: String? = nil, timeoutSeconds: TimeInterval = 5.0) -> (reloadResult: ProcessResult, healthResult: ProcessResult, freshGeneration: String?) {
        let reloadResult: ProcessResult
        do {
            reloadResult = try runHsReload()
        } catch {
            let errResult = ProcessResult(exitCode: 1, stdout: "", stderr: "Reload process invocation error: \(error.localizedDescription)")
            return (errResult, errResult, nil)
        }

        let expectedTransportInvalidation = !reloadResult.isSuccess && isExpectedReloadTransportInvalidation(reloadResult)
        if !reloadResult.isSuccess && !expectedTransportInvalidation {
            return (reloadResult, ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: "Reload command failed: \(reloadResult.stderr)"), nil)
        }

        let startTime = Date()
        var lastSentinel: RuntimeSentinelInfo? = nil
        var lastQueryResult = ProcessResult(exitCode: 1, stdout: "", stderr: "")

        while Date().timeIntervalSince(startTime) < timeoutSeconds {
            let (qRes, sentinel) = queryRuntimeSentinel()
            lastQueryResult = qRes
            lastSentinel = sentinel

            if let s = sentinel, s.version == 1, s.isReady {
                if let prevGen = previousGeneration, !prevGen.isEmpty {
                    if s.generation != prevGen && !s.generation.isEmpty {
                        return (
                            verifiedReloadResult(reloadResult, expectedTransportInvalidation: expectedTransportInvalidation),
                            ProcessResult(exitCode: 0, stdout: "HEALTHY_V1", stderr: ""),
                            s.generation
                        )
                    }
                } else if !s.generation.isEmpty {
                    return (
                        verifiedReloadResult(reloadResult, expectedTransportInvalidation: expectedTransportInvalidation),
                        ProcessResult(exitCode: 0, stdout: "HEALTHY_V1", stderr: ""),
                        s.generation
                    )
                }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let reason: String
        if !lastQueryResult.isSuccess {
            reason = "Sentinel query failed: \(lastQueryResult.stderr)"
        } else if let s = lastSentinel {
            if s.version != 1 {
                reason = "Unsupported sentinel version \(s.version) (expected 1)"
            } else if !s.isReady {
                reason = "Sentinel ready flag is false"
            } else if let prevGen = previousGeneration, s.generation == prevGen {
                reason = "Stale runtime generation detected after reload (\(prevGen))"
            } else {
                reason = "Sentinel query timed out after \(timeoutSeconds)s"
            }
        } else {
            reason = "Sentinel missing (_G.hsControlSentinel is nil)"
        }

        return (reloadResult, ProcessResult(exitCode: 1, stdout: "NOT_READY", stderr: reason), lastSentinel?.generation)
    }

    private func isExpectedReloadTransportInvalidation(_ result: ProcessResult) -> Bool {
        let diagnostic = "\(result.stdout)\n\(result.stderr)".lowercased()
        return diagnostic.contains("transport errors are normal if hammerspoon is reloading") ||
            diagnostic.contains("message port was invalidated") ||
            diagnostic.contains("dropping corrupt reply mach message")
    }

    private func verifiedReloadResult(
        _ originalResult: ProcessResult,
        expectedTransportInvalidation: Bool
    ) -> ProcessResult {
        guard expectedTransportInvalidation else { return originalResult }
        return ProcessResult(
            exitCode: 0,
            stdout: "Reload completed; transient Hammerspoon IPC disconnect was followed by a fresh healthy runtime.",
            stderr: ""
        )
    }

    #if DEBUG
    /// Test hook for exercising the real subprocess path — pipe draining and timeout
    /// handling cannot be covered through the injected `launcher`.
    func runCommandForTesting(_ command: CommandDescriptor) throws -> ProcessResult {
        try executeCommand(command)
    }
    #endif

    private func executeCommand(_ command: CommandDescriptor) throws -> ProcessResult {
        if let launcher = launcher {
            return try launcher(command)
        }

        guard FileManager.default.fileExists(atPath: command.executablePath) else {
            return ProcessResult(exitCode: 1, stdout: "", stderr: "Executable not found at \(command.executablePath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executablePath)
        process.arguments = command.arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // `hs` treats a piped stdin as interactive mode and waits for input forever, so
        // hand it an explicit empty stdin instead of the pipe Process would default to.
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        let startedAt = Date()
        try process.run()

        // Drain both pipes concurrently. Reading only after the process exits deadlocks any
        // child that writes more than the ~64KB pipe buffer: it blocks on write, never
        // exits, and the timeout below fires on what was really a working command.
        let drained = DispatchGroup()
        let collector = OutputCollector()
        drain(stdoutPipe.fileHandleForReading, into: drained) { collector.appendStdout($0) }
        drain(stderrPipe.fileHandleForReading, into: drained) { collector.appendStderr($0) }

        let finishedInTime = exited.wait(timeout: .now() + command.timeoutSeconds) == .success
        if !finishedInTime {
            terminateHard(process)
            _ = drained.wait(timeout: .now() + 2.0)
            AppLog.commandFinished(
                executable: command.executablePath,
                arguments: command.arguments,
                exitCode: 124,
                duration: Date().timeIntervalSince(startedAt)
            )
            return ProcessResult(
                exitCode: 124,
                stdout: collector.stdoutText,
                stderr: "Command timed out after \(command.timeoutSeconds)s: \(command.executablePath) \(command.arguments.joined(separator: " "))"
            )
        }

        _ = drained.wait(timeout: .now() + 2.0)
        process.waitUntilExit()

        AppLog.commandFinished(
            executable: command.executablePath,
            arguments: command.arguments,
            exitCode: process.terminationStatus,
            duration: Date().timeIntervalSince(startedAt)
        )

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: collector.stdoutText,
            stderr: collector.stderrText
        )
    }

    private func drain(_ handle: FileHandle, into group: DispatchGroup, store: @escaping (Data) -> Void) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = handle.readDataToEndOfFile()
            store(data)
            group.leave()
        }
    }

    /// SIGTERM first, then SIGKILL if the child ignores it. `terminate()` alone leaves a
    /// process that traps SIGTERM running forever.
    private func terminateHard(_ process: Process) {
        process.terminate()
        let deadline = Date().addingTimeInterval(0.5)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
    }
}

/// Accumulates pipe output from the two reader threads.
private final class OutputCollector {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        stdoutData.append(data)
    }

    func appendStderr(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        stderrData.append(data)
    }

    var stdoutText: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var stderrText: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
