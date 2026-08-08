import XCTest
@testable import HammerspoonControl

final class ProcessRunnerTests: XCTestCase {

    func testProcessRunnerPathsAndDependencyCheck() {
        let runner = ProcessRunner(
            customHsPath: "/opt/homebrew/bin/hs",
            customNightlightPath: "/opt/homebrew/bin/nightlight",
            customAppPath: "/Applications/Hammerspoon.app"
        )

        XCTAssertEqual(runner.hsExecutablePath, "/opt/homebrew/bin/hs")
        XCTAssertEqual(runner.nightlightExecutablePath, "/opt/homebrew/bin/nightlight")
        XCTAssertEqual(runner.hammerspoonAppPath, "/Applications/Hammerspoon.app")

        let deps = runner.checkDependencies()
        XCTAssertEqual(deps.count, 3)
        XCTAssertEqual(deps[0].id, "hammerspoon")
        XCTAssertEqual(deps[1].id, "hs")
        XCTAssertEqual(deps[2].id, "nightlight")
    }

    func testRunHsReloadFailsGracefullyWhenExecutableMissing() throws {
        let runner = ProcessRunner(
            customHsPath: "/nonexistent/path/to/hs",
            customNightlightPath: "/nonexistent/nightlight",
            customAppPath: "/nonexistent/App.app"
        )

        let result = try runner.runHsReload()
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.stderr.contains("not found"))
    }

    func testRunHsReloadAssertsExactExecutableAndArguments() throws {
        var recordedCommands: [CommandDescriptor] = []

        let runner = ProcessRunner(
            launcher: { command in
                recordedCommands.append(command)
                return ProcessResult(exitCode: 0, stdout: "reloaded", stderr: "")
            }
        )

        let result = try runner.runHsReload()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(recordedCommands.count, 1)
        XCTAssertEqual(recordedCommands[0].executablePath, "/opt/homebrew/bin/hs")
        XCTAssertEqual(recordedCommands[0].arguments, ["-c", "hs.reload()"])
    }

    func testQueryRuntimeHealthAssertsExactExecutableAndArguments() throws {
        var recordedCommands: [CommandDescriptor] = []

        let runner = ProcessRunner(
            launcher: { command in
                recordedCommands.append(command)
                return ProcessResult(exitCode: 0, stdout: "V=1;READY=true;GEN=gen_123", stderr: "")
            }
        )

        let result = runner.queryRuntimeHealth()

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(recordedCommands.count, 1)
        XCTAssertEqual(recordedCommands[0].executablePath, "/opt/homebrew/bin/hs")
        XCTAssertEqual(recordedCommands[0].arguments.count, 2)
        XCTAssertEqual(recordedCommands[0].arguments[0], "-c")
        XCTAssertTrue(recordedCommands[0].arguments[1].contains("_G.hsControlSentinel"))
    }

    func testQueryRuntimeHealthWithMissingSentinel() {
        let runner = ProcessRunner(
            launcher: { _ in ProcessResult(exitCode: 0, stdout: "NOT_PRESENT", stderr: "") }
        )
        let health = runner.queryRuntimeHealth()
        XCTAssertFalse(health.isSuccess)
        XCTAssertTrue(health.stderr.contains("Sentinel missing"))
    }

    func testQueryRuntimeHealthWithReadyFalse() {
        let runner = ProcessRunner(
            launcher: { _ in ProcessResult(exitCode: 0, stdout: "V=1;READY=false;GEN=gen_1", stderr: "") }
        )
        let health = runner.queryRuntimeHealth()
        XCTAssertFalse(health.isSuccess)
        XCTAssertTrue(health.stderr.contains("ready flag is false"))
    }

    func testQueryRuntimeHealthWithWrongVersion() {
        let runner = ProcessRunner(
            launcher: { _ in ProcessResult(exitCode: 0, stdout: "V=2;READY=true;GEN=gen_1", stderr: "") }
        )
        let health = runner.queryRuntimeHealth()
        XCTAssertFalse(health.isSuccess)
        XCTAssertTrue(health.stderr.contains("Unsupported sentinel version 2"))
    }

    func testReloadAndVerifyHealthStaleGeneration() {
        let runner = ProcessRunner(
            launcher: { command in
                if command.arguments.contains("hs.reload()") {
                    return ProcessResult(exitCode: 0, stdout: "reloaded", stderr: "")
                } else {
                    return ProcessResult(exitCode: 0, stdout: "V=1;READY=true;GEN=old_gen", stderr: "")
                }
            }
        )

        let res = runner.reloadAndVerifyHealth(previousGeneration: "old_gen", timeoutSeconds: 0.1)
        XCTAssertTrue(res.reloadResult.isSuccess)
        XCTAssertFalse(res.healthResult.isSuccess)
        XCTAssertTrue(res.healthResult.stderr.contains("Stale runtime generation detected"))
    }

    func testReloadAndVerifyHealthFreshGeneration() {
        var queryCallCount = 0
        let runner = ProcessRunner(
            launcher: { command in
                if command.arguments.contains("hs.reload()") {
                    return ProcessResult(exitCode: 0, stdout: "reloaded", stderr: "")
                } else {
                    queryCallCount += 1
                    let gen = queryCallCount == 1 ? "old_gen" : "new_gen"
                    return ProcessResult(exitCode: 0, stdout: "V=1;READY=true;GEN=\(gen)", stderr: "")
                }
            }
        )

        let res = runner.reloadAndVerifyHealth(previousGeneration: "old_gen", timeoutSeconds: 1.0)
        XCTAssertTrue(res.reloadResult.isSuccess)
        XCTAssertTrue(res.healthResult.isSuccess)
        XCTAssertEqual(res.freshGeneration, "new_gen")
    }

    func testReloadAndVerifyHealthCLIFailure() {
        let runner = ProcessRunner(
            launcher: { command in
                if command.arguments.contains("hs.reload()") {
                    return ProcessResult(exitCode: 1, stdout: "", stderr: "IPC server unreachable")
                } else {
                    return ProcessResult(exitCode: 0, stdout: "NOT_PRESENT", stderr: "")
                }
            }
        )

        let res = runner.reloadAndVerifyHealth(previousGeneration: nil, timeoutSeconds: 0.1)
        XCTAssertFalse(res.reloadResult.isSuccess)
        XCTAssertFalse(res.healthResult.isSuccess)
        XCTAssertTrue(res.healthResult.stderr.contains("Reload command failed"))
    }

    func testReloadAndVerifyHealthAcceptsExpectedTransportInvalidationAfterFreshSentinel() {
        var queryCallCount = 0
        let runner = ProcessRunner(
            launcher: { command in
                if command.arguments.contains("hs.reload()") {
                    return ProcessResult(
                        exitCode: 1,
                        stdout: "",
                        stderr: "error communicating with Hammerspoon: message port was invalidated (transport errors are normal if Hammerspoon is reloading)"
                    )
                }

                queryCallCount += 1
                let generation = queryCallCount == 1 ? "old_gen" : "fresh_gen"
                return ProcessResult(exitCode: 0, stdout: "V=1;READY=true;GEN=\(generation)", stderr: "")
            }
        )

        let res = runner.reloadAndVerifyHealth(previousGeneration: "old_gen", timeoutSeconds: 1.0)

        XCTAssertTrue(res.reloadResult.isSuccess)
        XCTAssertTrue(res.reloadResult.stdout.contains("transient Hammerspoon IPC disconnect"))
        XCTAssertTrue(res.healthResult.isSuccess)
        XCTAssertEqual(res.freshGeneration, "fresh_gen")
    }

    func testReloadAndVerifyHealthDoesNotHideTransportInvalidationWithoutFreshSentinel() {
        let runner = ProcessRunner(
            launcher: { command in
                if command.arguments.contains("hs.reload()") {
                    return ProcessResult(
                        exitCode: 1,
                        stdout: "",
                        stderr: "CFMessagePort: dropping corrupt reply Mach message; message port was invalidated"
                    )
                }
                return ProcessResult(exitCode: 0, stdout: "V=1;READY=true;GEN=old_gen", stderr: "")
            }
        )

        let res = runner.reloadAndVerifyHealth(previousGeneration: "old_gen", timeoutSeconds: 0.1)

        XCTAssertFalse(res.reloadResult.isSuccess)
        XCTAssertFalse(res.healthResult.isSuccess)
        XCTAssertTrue(res.healthResult.stderr.contains("Stale runtime generation detected"))
    }

    func testFixedExecutablePathAndArguments() throws {
        let runner = ProcessRunner()
        XCTAssertEqual(runner.hsExecutablePath, "/opt/homebrew/bin/hs")
        XCTAssertEqual(runner.nightlightExecutablePath, "/opt/homebrew/bin/nightlight")
    }

    // MARK: - Sentinel parsing
    //
    // Hammerspoon prepends "-- Loading extension: ..." whenever a Lua module autoloads, so
    // the sentinel record is not guaranteed to be the entirety of stdout.

    func testSentinelParsingIgnoresHammerspoonExtensionLoadNoise() {
        let noisy = "-- Loading extension: settings\n-- Loading extension: timer\nV=1;READY=true;GEN=1786204485.03_450897"
        let sentinel = ProcessRunner.parseSentinel(noisy)

        XCTAssertEqual(sentinel?.version, 1)
        XCTAssertEqual(sentinel?.isReady, true)
        XCTAssertEqual(sentinel?.generation, "1786204485.03_450897")
    }

    func testHealthCheckIsHealthyDespiteNoisyStdout() {
        let runner = ProcessRunner(launcher: { _ in
            ProcessResult(exitCode: 0, stdout: "-- Loading extension: settings\nV=1;READY=true;GEN=gen_1", stderr: "")
        })

        let health = runner.queryRuntimeHealth()

        XCTAssertTrue(health.isSuccess)
        XCTAssertTrue(health.stdout.contains("HEALTHY_V1"))
    }

    func testSentinelParsingHandlesNotPresentAndGarbage() {
        XCTAssertNil(ProcessRunner.parseSentinel("NOT_PRESENT"))
        XCTAssertNil(ProcessRunner.parseSentinel("-- Loading extension: settings\nNOT_PRESENT"))
        XCTAssertNil(ProcessRunner.parseSentinel(""))
        XCTAssertNil(ProcessRunner.parseSentinel("something entirely unexpected"))
    }

    // MARK: - Subprocess I/O

    /// Reading the pipes only after the process exits deadlocks any child that outgrows the
    /// ~64KB pipe buffer: it blocks on write, never exits, and the timeout fires on a command
    /// that was working fine.
    func testLargeStdoutDoesNotDeadlockOrTimeOut() throws {
        let payload = String(repeating: "abcdefghij", count: 40_000) // ~400KB, far past the buffer
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hsc-large-stdout-\(UUID().uuidString).txt")
        try payload.write(to: scratch, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let runner = ProcessRunner(customHsPath: "/bin/cat")
        let result = try runner.runCommandForTesting(
            CommandDescriptor(executablePath: "/bin/cat", arguments: [scratch.path], timeoutSeconds: 10.0)
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, payload.count)
    }

    func testTimeoutReportsExitCode124AndDoesNotWaitForTheChild() throws {
        let runner = ProcessRunner()

        let started = Date()
        let result = try runner.runCommandForTesting(
            CommandDescriptor(executablePath: "/bin/sleep", arguments: ["30"], timeoutSeconds: 0.5)
        )
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertEqual(result.exitCode, 124)
        XCTAssertTrue(result.stderr.contains("timed out"))
        XCTAssertLessThan(elapsed, 5.0, "Timeout must not wait out the full child duration")
    }
}
