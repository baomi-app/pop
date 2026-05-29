import ScreenCaptureKit
import CoreGraphics
import AppKit

enum CaptureError: Error {
    case noDisplay
    case noWindow
    case encodeFailed
}

/// 基于 ScreenCaptureKit 的静态截图服务（macOS 14+）。
enum ScreenCaptureService {

    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    // MARK: - 全屏

    /// 按 NSScreen 截全屏。
    static func captureFullScreen(of screen: NSScreen) async throws -> CGImage {
        let content = try await shareableContent()
        let display = content.displays.first { $0.displayID == screen.displayID }
            ?? content.displays.first
        guard let display else { throw CaptureError.noDisplay }
        return try await capture(display: display, cropRect: nil, scale: scale(for: display))
    }

    // MARK: - 区域

    /// cropRect：display 坐标系内、左上角为原点的「点」矩形。
    static func captureRegion(_ cropRect: CGRect, on display: SCDisplay) async throws -> CGImage {
        try await capture(display: display, cropRect: cropRect, scale: scale(for: display))
    }

    // MARK: - 窗口

    /// 按指定 SCWindow 截图。
    static func capture(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let s = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(window.frame.width * s)
        config.height = Int(window.frame.height * s)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: - 核心

    private static func capture(display: SCDisplay, cropRect: CGRect?, scale: CGFloat) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let cropRect else { return full }

        let px = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        return full.cropping(to: px) ?? full
    }

    // MARK: - 工具

    static func scale(for display: SCDisplay) -> CGFloat {
        NSScreen.screens.first { $0.displayID == display.displayID }?.backingScaleFactor ?? 2.0
    }

    /// 把「全局屏幕坐标（左下原点）」矩形转成「display 局部、左上原点」的点矩形。
    static func topLeftRect(_ rect: CGRect, in screen: NSScreen) -> CGRect {
        let f = screen.frame
        return CGRect(
            x: rect.minX - f.minX,
            y: f.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
