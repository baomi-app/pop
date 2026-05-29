import SwiftUI

/// baomi Pop — the first kernel.
/// A menu-bar-resident screenshot tool for macOS. Snap, and it pops.
@main
struct PopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image("MenuBarIconImage")
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
