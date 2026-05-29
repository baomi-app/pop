import SwiftUI

/// 苞米 Pop —— 第一粒。
/// 一个常驻菜单栏的 macOS 截图工具。咔，一爆即得。
@main
struct PopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(history)
        } label: {
            Image(systemName: "dot.viewfinder")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏 App，不在 Dock 显示
        NSApp.setActivationPolicy(.accessory)
        HotkeyManager.shared.start()
    }
}
