import Foundation
import os

/// Local-only structured logging. Diagnosing the "button does nothing" report meant
/// reverse-engineering the source, because the app kept no record of what it ran, what
/// came back, or which errors it swallowed. Everything here goes to the unified log and
/// never leaves the machine; read it with:
///
///     log stream --predicate 'subsystem == "com.gabrielblacher.HammerspoonControl"'
public enum AppLog {
    private static let subsystem = "com.gabrielblacher.HammerspoonControl"

    public static let process = Logger(subsystem: subsystem, category: "process")
    public static let integration = Logger(subsystem: subsystem, category: "integration")

    public static func commandFinished(
        executable: String,
        arguments: [String],
        exitCode: Int32,
        duration: TimeInterval
    ) {
        let args = arguments.joined(separator: " ")
        let millis = Int(duration * 1000)
        if exitCode == 0 {
            process.debug("ran \(executable, privacy: .public) \(args, privacy: .public) -> exit 0 in \(millis)ms")
        } else {
            process.error("ran \(executable, privacy: .public) \(args, privacy: .public) -> exit \(exitCode) in \(millis)ms")
        }
    }
}
