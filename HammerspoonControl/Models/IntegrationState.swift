import Foundation

public enum IntegrationState: Equatable {
    case missingDependencies([SystemDependency])
    case readyToInstall(backupPathToCreate: String, initSha256: String)
    case installed(manifest: InstallManifest)
    case installedRuntimeInactive(manifest: InstallManifest, reason: String)
    case outdatedRuntime(manifest: InstallManifest)
    case outdatedBootstrap(manifest: InstallManifest)
    case unsafeUnrecognizedConfig(reason: String)

    public var statusDescription: String {
        switch self {
        case .missingDependencies(let deps):
            let names = deps.map { $0.displayName }.joined(separator: ", ")
            return "Missing required dependencies: \(names)"
        case .readyToInstall(_, let hash):
            return "Ready to install. Pre-app baseline matched (SHA: \(hash.prefix(8))...)"
        case .installed:
            return "Hammerspoon Control integration is active and up to date."
        case .installedRuntimeInactive(_, let reason):
            return "Files installed, but Lua runtime is inactive or health check failed: \(reason)"
        case .outdatedRuntime:
            return "Managed integration installed, but runtime file requires an update."
        case .outdatedBootstrap:
            return "Managed integration installed, but init.lua uses an older recognized bootstrap and requires an update."
        case .unsafeUnrecognizedConfig(let reason):
            return "Automatic migration refused: \(reason)"
        }
    }
}
