import Foundation

public struct InstallManifest: Codable, Equatable {
    public var version: Int
    public var installedAt: Date
    public var originalInitSha256: String
    public var originalInitBackupPath: String
    public var runtimeSha256: String

    public init(
        version: Int = 1,
        installedAt: Date = Date(),
        originalInitSha256: String,
        originalInitBackupPath: String,
        runtimeSha256: String
    ) {
        self.version = version
        self.installedAt = installedAt
        self.originalInitSha256 = originalInitSha256
        self.originalInitBackupPath = originalInitBackupPath
        self.runtimeSha256 = runtimeSha256
    }
}
