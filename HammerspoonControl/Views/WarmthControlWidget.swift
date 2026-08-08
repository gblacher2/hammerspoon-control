import SwiftUI
import WidgetKit
import AppIntents

@available(macOS 26.0, *)
public struct WarmthControlWidget: ControlWidget {
    public static let kind: String = "com.gabrielblacher.HammerspoonControl.WarmthControlWidget"

    public init() {}

    @available(macOS 26.0, *)
    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: PauseWarmthIntent()) {
                Label("Pause Warmth 1h", systemImage: "pause.circle.fill")
            }
        }
        .displayName("Pause Warmth")
        .description("Pauses external display warmth for 1 hour.")
    }
}

@available(macOS 26.0, *)
public struct ToggleWarmthControlWidget: ControlWidget {
    public static let kind: String = "com.gabrielblacher.HammerspoonControl.ToggleWarmthControlWidget"

    public init() {}

    @available(macOS 26.0, *)
    public var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ToggleWarmthIntent()) {
                Label("Toggle Warmth", systemImage: "sun.max.fill")
            }
        }
        .displayName("Toggle Warmth")
        .description("Toggles display warmth on or off.")
    }
}
