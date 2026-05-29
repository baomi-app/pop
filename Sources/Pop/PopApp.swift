import SwiftUI

/// baomi Pop — the first kernel.
/// A menu-bar-resident screenshot tool for macOS. Snap, and it pops.
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
        // Menu-bar app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)
        HotkeyManager.shared.start()
    }
}
