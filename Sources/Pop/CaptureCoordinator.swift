import AppKit
import ScreenCaptureKit
import CoreGraphics

/// Capture flow orchestration.
/// - Region: capture → in-place annotation overlay → user copies/saves there.
/// - Window / full screen: capture → copy to clipboard + save + record + "pop" feedback.
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
                // Full screen: capture and finalize directly (no in-place editing for v1).
                Task {
                    await self.captureThenFinalize {
                        try await ScreenCaptureService.captureFullScreen(of: screen)
                    }
                }

            case .window(let win):
                // Window: capture and finalize directly (no in-place editing for v1).
                Task {
                    await self.captureThenFinalize {
                        try await ScreenCaptureService.capture(win)
                    }
                }

            case .region(let screenRect):
                // Region: capture, then open the in-place annotation overlay.
                // The selection overlay stays up (dimmed) through capture and is
                // dismissed only after the annotation overlay is shown, so there's no
                // bright flash. Our own overlay windows are excluded from the capture
                // so the dimming/selection chrome never ends up in the screenshot.
                Task {
                    do {
                        let content = try await ScreenCaptureService.shareableContent()
                        let display = content.displays.first { $0.displayID == screen.displayID }
                            ?? content.displays.first
                        guard let display else { throw CaptureError.noDisplay }
                        let myBundle = Bundle.main.bundleIdentifier
                        let ownWindows = content.windows.filter {
                            $0.owningApplication?.bundleIdentifier == myBundle
                        }
                        let crop = ScreenCaptureService.topLeftRect(screenRect, in: screen)
                        let image = try await ScreenCaptureService.captureRegion(
                            crop, on: display, excluding: ownWindows)
                        // present() tears down the selection overlay itself, but only
                        // after the annotation overlay has drawn a frame — preventing a
                        // one-frame desktop flash.
                        AnnotationOverlayController.shared.present(
                            base: image, rectGlobal: screenRect, screen: screen)
                    } catch {
                        NSLog("[Pop] Capture failed: \(error)")
                        RegionSelectionController.shared.dismiss()
                    }
                }
            }
        }
    }

    // MARK: -

    private func captureThenFinalize(_ capture: @escaping () async throws -> CGImage) async {
        do {
            let image = try await capture()
            CaptureCoordinator.finalize(image)
        } catch {
            NSLog("[Pop] Capture failed: \(error)")
        }
    }

    /// Copy to clipboard + (optionally) save to disk + (optionally) "pop" feedback.
    static func finalize(_ cgImage: CGImage) {
        ClipboardService.copy(cgImage)

        let store = HotkeyStore.shared
        if store.saveEnabled, let dir = store.savePath {
            do {
                try ImageSaver.savePNG(cgImage, to: dir)
            } catch {
                NSLog("[Pop] Save to disk failed: \(error)")
            }
        }

        if store.toastEnabled {
            Toast.show(Brand.Copy.saved)
        }
    }
}
