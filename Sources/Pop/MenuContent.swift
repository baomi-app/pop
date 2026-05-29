import SwiftUI
import AppKit

/// Menu-bar dropdown content.
struct MenuContent: View {
    @EnvironmentObject var history: HistoryStore
    @ObservedObject var hotkeys: HotkeyStore = .shared

    var body: some View {
        Button("截一粒（\(hotkeys.config.displayString)）") {
            CaptureCoordinator.shared.unified()
        }

        Divider()

        Text(Brand.Copy.todayCount(history.todayCount))

        Button("偏好设置…") {
            SettingsWindowController.shared.show()
        }

        Divider()

        Button("退出 Pop") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
