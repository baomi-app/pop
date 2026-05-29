import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

/// 统一截图选择层（覆盖全部屏幕）。
/// - 鼠标悬停：高亮命中窗口
/// - 单击：截击中窗口
/// - 拖拽：区域截图
/// - Return / Enter：全屏（取光标所在屏幕）
/// - Esc：取消
enum CaptureIntent {
    case region(CGRect)        // NSScreen 全局坐标（左下原点）
    case window(SCWindow)
    case fullScreen
    case cancel
}

@MainActor
final class RegionSelectionController {
    static let shared = RegionSelectionController()

    private var windows: [SelectionWindow] = []
    private var keyMonitor: Any?

    func begin(_ completion: @escaping (CaptureIntent, NSScreen) -> Void) {
        guard windows.isEmpty else {
            completion(.cancel, NSScreen.main ?? NSScreen.screens[0])
            return
        }

        Task {
            let snapshot = (try? await ScreenCaptureService.shareableContent().windows) ?? []
            let myBundle = Bundle.main.bundleIdentifier
            let candidates = snapshot.filter { win in
                win.isOnScreen
                    && win.owningApplication != nil
                    && win.owningApplication?.bundleIdentifier != myBundle
                    && win.windowLayer == 0                 // 仅普通应用窗口（排除 Dock、壁纸、菜单）
                    && win.frame.width > 40 && win.frame.height > 40
            }
            await MainActor.run {
                self.present(candidates: candidates, completion: completion)
            }
        }
    }

    private func present(candidates: [SCWindow], completion: @escaping (CaptureIntent, NSScreen) -> Void) {
        let finish: (CaptureIntent, NSScreen) -> Void = { [weak self] intent, screen in
            self?.dismiss()
            completion(intent, screen)
        }

        for screen in NSScreen.screens {
            let win = SelectionWindow(screen: screen, candidates: candidates)
            win.onIntent = { intent in finish(intent, screen) }
            windows.append(win)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !self.windows.isEmpty else { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                finish(.cancel, NSScreen.main ?? NSScreen.screens[0])
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                let screen = self.screenUnderCursor()
                finish(.fullScreen, screen)
                return nil
            default:
                return event
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        for win in windows {
            win.orderFrontRegardless()
        }
        windows.first?.makeKey()

        // 出现后立刻按当前鼠标位置触发一次高亮，避免必须先移动鼠标
        let mouse = NSEvent.mouseLocation
        for win in windows where win.frame.contains(mouse) {
            (win.contentView as? SelectionView)?.updateHoverFromGlobalMouse()
        }
    }

    private func dismiss() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        for win in windows { win.orderOut(nil) }
        windows.removeAll()
    }

    private func screenUnderCursor() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

// MARK: - 选择窗口

final class SelectionWindow: NSWindow {
    var onIntent: ((CaptureIntent) -> Void)?

    init(screen: NSScreen, candidates: [SCWindow]) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        setFrame(screen.frame, display: true)

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                 candidates: candidates)
        view.onLocalIntent = { [weak self] localIntent in
            guard let self else { return }
            switch localIntent {
            case .region(let r):
                self.onIntent?(.region(self.convertToScreen(r)))
            case .window(let w):
                self.onIntent?(.window(w))
            case .fullScreen:
                self.onIntent?(.fullScreen)
            case .cancel:
                self.onIntent?(.cancel)
            }
        }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - 选择视图

private enum LocalIntent {
    case region(NSRect)
    case window(SCWindow)
    case fullScreen
    case cancel
}

final class SelectionView: NSView {
    fileprivate var onLocalIntent: ((LocalIntent) -> Void)?

    private let candidates: [SCWindow]

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var didDrag = false
    private var hoveredWindow: SCWindow?
    private var hoveredLocalRect: NSRect?
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, candidates: [SCWindow]) {
        self.candidates = candidates
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        guard !didDrag, startPoint == nil else { return }
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoveredWindow = nil
        hoveredLocalRect = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(origin: startPoint!, size: .zero)
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        let r = NSRect(
            x: min(start.x, p.x),
            y: min(start.y, p.y),
            width: abs(p.x - start.x),
            height: abs(p.y - start.y)
        )
        currentRect = r
        if r.width > 4 || r.height > 4 {
            didDrag = true
            hoveredWindow = nil
            hoveredLocalRect = nil
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            currentRect = nil
            didDrag = false
            needsDisplay = true
        }
        if didDrag, let rect = currentRect, rect.width > 4, rect.height > 4 {
            onLocalIntent?(.region(rect))
        } else {
            // 单击：截当前悬停的窗口
            if let win = hoveredWindow {
                onLocalIntent?(.window(win))
            }
        }
    }

    func updateHoverFromGlobalMouse() {
        guard let win = window else { return }
        let global = NSEvent.mouseLocation
        let local = convert(win.convertPoint(fromScreen: global), from: nil)
        updateHover(at: local)
    }

    private func updateHover(at localPoint: NSPoint) {
        guard let (win, localRect) = topmostWindow(atLocal: localPoint) else {
            if hoveredWindow != nil {
                hoveredWindow = nil
                hoveredLocalRect = nil
                needsDisplay = true
            }
            return
        }
        if win.windowID != hoveredWindow?.windowID {
            hoveredWindow = win
            hoveredLocalRect = localRect
            needsDisplay = true
        }
    }

    /// 找到本视图局部坐标 `localPoint` 下的最上层 SCWindow。
    /// 返回 (SCWindow, 局部矩形)。
    private func topmostWindow(atLocal localPoint: NSPoint) -> (SCWindow, NSRect)? {
        guard let win = window else { return nil }
        let globalPoint = win.convertPoint(toScreen: localPoint)
        let primary = Self.primaryScreen()
        let cgPoint = CGPoint(x: globalPoint.x, y: primary.frame.maxY - globalPoint.y)
        guard let hit = candidates.first(where: { $0.frame.contains(cgPoint) }) else { return nil }

        // SCWindow.frame (CG, top-left) → global NSScreen (bottom-left) → window local → view local
        let nsRect = NSRect(
            x: hit.frame.origin.x,
            y: primary.frame.maxY - hit.frame.origin.y - hit.frame.height,
            width: hit.frame.width,
            height: hit.frame.height
        )
        let winRect = win.convertFromScreen(nsRect)
        let viewRect = convert(winRect, from: nil)
        return (hit, viewRect)
    }

    /// CG 坐标原点在的那个屏幕（NSScreen frame.origin == .zero）。
    private static func primaryScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        drawHint()

        // 区域选择优先
        if let rect = currentRect, didDrag {
            NSColor.clear.setFill()
            rect.fill(using: .copy)

            let border = NSBezierPath(rect: rect)
            border.lineWidth = 2
            NSColor(calibratedRed: 1.0, green: 0.823, blue: 0.290, alpha: 1).setStroke()
            border.stroke()

            let label = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = label.size(withAttributes: attrs)
            let labelOrigin = NSPoint(x: rect.minX, y: rect.maxY + 6)
            let bg = NSRect(x: labelOrigin.x - 4, y: labelOrigin.y - 2, width: size.width + 8, height: size.height + 4)
            NSColor(calibratedRed: 0.353, green: 0.227, blue: 0.118, alpha: 0.9).setFill()
            NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
            label.draw(at: labelOrigin, withAttributes: attrs)
            return
        }

        // 窗口高亮
        if let rect = hoveredLocalRect {
            let clipped = rect.intersection(bounds)
            guard !clipped.isNull, !clipped.isEmpty else { return }
            NSColor.clear.setFill()
            clipped.fill(using: .copy)

            let border = NSBezierPath(rect: clipped)
            border.lineWidth = 3
            NSColor(calibratedRed: 1.0, green: 0.823, blue: 0.290, alpha: 1).setStroke()
            border.stroke()
        }
    }

    private func drawHint() {
        let hint = String(localized: "悬停=窗口 · 拖拽=区域 · ↩=全屏 · ⎋=取消") as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = hint.size(withAttributes: attrs)
        let x = (bounds.width - size.width) / 2
        let y = bounds.height - size.height - 28
        let pad: CGFloat = 10
        let bg = NSRect(x: x - pad, y: y - pad/2, width: size.width + 2*pad, height: size.height + pad)
        NSColor(calibratedRed: 0.353, green: 0.227, blue: 0.118, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 8, yRadius: 8).fill()
        hint.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    }
}
