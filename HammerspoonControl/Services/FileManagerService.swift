import Foundation
import CryptoKit

public protocol FileManagerServiceProtocol {
    var configDirURL: URL { get }
    var hammerspoonControlDirURL: URL { get }
    var initLuaURL: URL { get }
    var settingsJsonURL: URL { get }
    var runtimeLuaURL: URL { get }
    var installJsonURL: URL { get }

    func sha256(of url: URL) throws -> String
    func sha256(of data: Data) -> String
    func sha256(of text: String) -> String

    func fileExists(at url: URL) -> Bool
    func readText(at url: URL) throws -> String
    func readData(at url: URL) throws -> Data
    func atomicWrite(data: Data, to destinationURL: URL) throws
    func atomicWrite(text: String, to destinationURL: URL) throws

    func createCollisionSafeBackup(of sourceURL: URL, prefix: String) throws -> URL
    func ensureDirectoryExists(at url: URL) throws
}

public final class FileManagerService: FileManagerServiceProtocol {
    private let customConfigDirURL: URL?

    public init(customConfigDirURL: URL? = nil) {
        self.customConfigDirURL = customConfigDirURL
    }

    public var configDirURL: URL {
        if let custom = customConfigDirURL {
            return custom
        }
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["HAMMERSPOON_CONTROL_CONFIG_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hammerspoon")
    }

    public var hammerspoonControlDirURL: URL {
        configDirURL.appendingPathComponent("hammerspoon-control")
    }

    public var initLuaURL: URL {
        configDirURL.appendingPathComponent("init.lua")
    }

    public var settingsJsonURL: URL {
        hammerspoonControlDirURL.appendingPathComponent("settings.json")
    }

    public var runtimeLuaURL: URL {
        hammerspoonControlDirURL.appendingPathComponent("runtime.lua")
    }

    public var installJsonURL: URL {
        hammerspoonControlDirURL.appendingPathComponent("install.json")
    }

    public func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return sha256(of: data)
    }

    public func sha256(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    public func sha256(of text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        return sha256(of: data)
    }

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func readText(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    public func readData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func ensureDirectoryExists(at url: URL) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    public func atomicWrite(data: Data, to destinationURL: URL) throws {
        try ensureDirectoryExists(at: destinationURL.deletingLastPathComponent())
        let tempURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".tmp_\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)

        if fileExists(at: destinationURL) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        }
    }

    public func atomicWrite(text: String, to destinationURL: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "FileManagerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert text to UTF-8 data"])
        }
        try atomicWrite(data: data, to: destinationURL)
    }

    public func createCollisionSafeBackup(of sourceURL: URL, prefix: String = "init.lua.codex-backup") throws -> URL {
        guard fileExists(at: sourceURL) else {
            throw NSError(domain: "FileManagerService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Backup source file does not exist at \(sourceURL.path)"])
        }

        let parentDir = sourceURL.deletingLastPathComponent()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        let dateString = formatter.string(from: Date())
        var backupName = "\(prefix)-\(dateString)"
        var backupURL = parentDir.appendingPathComponent(backupName)

        var counter = 1
        while fileExists(at: backupURL) {
            backupName = "\(prefix)-\(dateString)-\(counter)"
            backupURL = parentDir.appendingPathComponent(backupName)
            counter += 1
        }

        let sourceData = try readData(at: sourceURL)
        try atomicWrite(data: sourceData, to: backupURL)
        return backupURL
    }
}
