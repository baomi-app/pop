import AppKit
import ScreenCaptureKit

/// 截图流程编排：触发捕获 → 复制剪贴板 + 保存文件 → 记历史 → "爆"反馈。
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    /// 统一截图模式：拖拽=区域，单击=窗口，回车=全屏，Esc=取消。
    func unified() {
        RegionSelectionController.shared.begin { [weak self] intent, screen in
            guard let self else { return }
            switch intent {
            case .cancel:
                return
            case .fullScreen:
                Task {
                    await self.run(scale: screen.backingScaleFactor) {
                        try await ScreenCaptureService.captureFullScreen(of: screen)
                    }
                }
            case .window(let win):
                Task {
                    await self.run(scale: screen.backingScaleFactor) {
                        try await ScreenCaptureService.capture(win)
                    }
                }
            case .region(let screenRect):
                Task {
                    await self.run(scale: screen.backingScaleFactor) {
                        let content = try await ScreenCaptureService.shareableContent()
                        let display = content.displays.first { $0.displayID == screen.displayID }
                            ?? content.displays.first
                        guard let display else { throw CaptureError.noDisplay }
                        let crop = ScreenCaptureService.topLeftRect(screenRect, in: screen)
                        return try await ScreenCaptureService.captureRegion(crop, on: display)
                    }
                }
            }
        }
    }

    // MARK: -

    private func run(scale: CGFloat, _ capture: @escaping () async throws -> CGImage) async {
        do {
            let image = try await capture()
            CaptureCoordinator.finalize(image)
        } catch {
            NSLog("[Pop] 截图失败：\(error)")
        }
    }

    /// 复制到剪贴板 +（可选）保存到本地 + 记历史 +（可选）"爆"反馈。
    static func finalize(_ cgImage: CGImage) {
        ClipboardService.copy(cgImage)

        let store = HotkeyStore.shared
        var fileURL: URL?
        if store.saveEnabled, let dir = store.savePath {
            do {
                fileURL = try ImageSaver.savePNG(cgImage, to: dir)
            } catch {
                NSLog("[Pop] 保存到本地失败：\(error)")
            }
        }

        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        HistoryStore.shared.recordPop(image: nsImage, fileURL: fileURL)

        if store.toastEnabled, !store.toastText.isEmpty {
            Toast.show(store.toastText)
        }
    }
}
