import AppKit
import ScreenCaptureKit
import CoreGraphics

/// Capture flow orchestration: trigger capture → copy to clipboard + save file → record history → "pop" feedback.
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    /// Unified capture mode: drag = region, click = window, Return = full screen, Esc = cancel.
    func unified() {
        // Verify Screen Recording permission first; otherwise the overlay is useless.
        guard CGPreflightScreenCaptureAccess() else {
            Toast.show(String(localized: "需要屏幕录制权限。授权后退出 Pop 再打开。"))
            // Trigger the system prompt (first time); otherwise open System Settings directly.
            if !CGRequestScreenCaptureAccess() {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

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
            NSLog("[Pop] Capture failed: \(error)")
        }
    }

    /// Copy to clipboard + (optionally) save to disk + record history + (optionally) "pop" feedback.
    static func finalize(_ cgImage: CGImage) {
        ClipboardService.copy(cgImage)

        let store = HotkeyStore.shared
        var fileURL: URL?
        if store.saveEnabled, let dir = store.savePath {
            do {
                fileURL = try ImageSaver.savePNG(cgImage, to: dir)
            } catch {
                NSLog("[Pop] Save to disk failed: \(error)")
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
