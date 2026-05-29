import AppKit
import Combine

/// 全局快捷键管理：用 Carbon RegisterEventHotKey（无需输入监控权限）。
/// 读 HotkeyStore.config，配置变化时自动重新注册。
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
