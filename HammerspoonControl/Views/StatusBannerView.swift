import SwiftUI

public struct StatusBannerView: View {
    let state: IntegrationState
    let isUnsaved: Bool
    let lastAppliedAt: Date?
    let lastReloadResult: ProcessResult?
    let errorMessage: String?

    public init(
        state: IntegrationState,
        isUnsaved: Bool,
        lastAppliedAt: Date?,
        lastReloadResult: ProcessResult?,
        errorMessage: String?
    ) {
        self.state = state
        self.isUnsaved = isUnsaved
        self.lastAppliedAt = lastAppliedAt
        self.lastReloadResult = lastReloadResult
        self.errorMessage = errorMessage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if isUnsaved {
                    Text("Unsaved Changes")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
            }

            if let lastAppliedAt = lastAppliedAt {
                Text("Last applied: \(formattedDate(lastAppliedAt))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if let reloadResult = lastReloadResult {
                HStack(spacing: 4) {
                    Image(systemName: reloadResult.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(reloadResult.isSuccess ? .green : .red)

                    Text(reloadResult.isSuccess ? "Hammerspoon reloaded successfully" : "Reload failed: \(reloadResult.stderr)")
                        .font(.system(size: 11))
                        .foregroundColor(reloadResult.isSuccess ? .secondary : .red)
                }
            }

            if case .installedRuntimeInactive(_, let reason) = state {
                Text("Diagnostic Reason: \(reason)")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .padding(6)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            }

            if let errorMsg = errorMessage, !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private var statusColor: Color {
        switch state {
        case .installed: return .green
        case .installedRuntimeInactive: return .orange
        case .readyToInstall: return .blue
        case .outdatedRuntime, .outdatedBootstrap: return .orange
        case .missingDependencies, .unsafeUnrecognizedConfig: return .red
        }
    }

    private var statusText: String {
        switch state {
        case .installed: return "Integration Active"
        case .installedRuntimeInactive: return "Runtime Inactive"
        case .readyToInstall: return "Integration Not Installed"
        case .outdatedRuntime: return "Integration Update Available"
        case .outdatedBootstrap: return "Bootstrap Update Available"
        case .missingDependencies: return "Missing Dependencies"
        case .unsafeUnrecognizedConfig: return "Migration Refused"
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
