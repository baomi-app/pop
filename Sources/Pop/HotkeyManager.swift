import Foundation
import Combine

/// Global hotkey manager backed by Carbon RegisterEventHotKey (no Input Monitoring permission needed).
/// Reads HotkeyStore.config and re-registers automatically whenever the config changes.
@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()

    private let carbon = CarbonHotkey()
    private var cancellable: AnyCancellable?

    func start() {
        apply(HotkeyStore.shared.config)
        cancellable = HotkeyStore.shared.$config
            .receive(on: RunLoop.main)
            .sink { [weak self] cfg in
                self?.apply(cfg)
            }
    }

    private func apply(_ cfg: HotkeyConfig) {
        carbon.register(keyCode: cfg.keyCode, modifiers: cfg.carbonModifiers) {
            CaptureCoordinator.shared.unified()
        }
    }
}
