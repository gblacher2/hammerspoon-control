import SwiftUI

@main
struct HammerspoonControlApp: App {
    @StateObject private var statusMonitor = StatusMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarExtraView(statusMonitor: statusMonitor)
        } label: {
            Image(systemName: statusMonitor.iconName)
        }
        .menuBarExtraStyle(.window)
    }
}
