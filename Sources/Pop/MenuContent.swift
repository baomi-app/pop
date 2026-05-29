import SwiftUI
import AppKit

/// Menu-bar dropdown content.
struct MenuContent: View {
    @ObservedObject var hotkeys: HotkeyStore = .shared

    var body: some View {
        Button("截一粒（\(hotkeys.config.displayString)）") {
            CaptureCoordinator.shared.unified()
        }

        Divider()

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
