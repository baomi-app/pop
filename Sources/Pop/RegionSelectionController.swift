import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

/// Unified capture selection overlay (covers every screen).
/// - Hover: highlight the window under the cursor
/// - Click: capture the hit window
/// - Drag: region capture
/// - Return / Enter: full screen (the screen under the cursor)
/// - Esc: cancel
enum CaptureIntent {
    case region(CGRect)        // Global NSScreen coordinates (bottom-left origin)
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
            let filtered = snapshot.filter { win in
                win.isOnScreen
                    && win.owningApplication != nil
                    && win.owningApplication?.bundleIdentifier != myBundle
                    && win.windowLayer == 0                 // Regular app windows only (exclude Dock, wallpaper, menus)
                    && win.frame.width > 40 && win.frame.height > 40
            }
            // SCShareableContent.windows is NOT reliably in z-order, so a hotkey-raised
            // (but unfocused) window could rank behind others and fail to snap. Re-sort
            // by the true front-to-back order from the window server.
            let zIndex = Self.zOrderIndex()
            let candidates = filtered.sorted {
                (zIndex[$0.windowID] ?? Int.max) < (zIndex[$1.windowID] ?? Int.max)
            }
            await MainActor.run {
                self.present(candidates: candidates, completion: completion)
            }
        }
    }

    /// Maps each on-screen window number to its front-to-back z-order index (0 = frontmost),
    /// taken from the window server, which — unlike SCShareableContent — is reliably ordered.
    private static func zOrderIndex() -> [CGWindowID: Int] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var map: [CGWindowID: Int] = [:]
        for (i, info) in list.enumerated() {
            if let n = info[kCGWindowNumber as String] as? CGWindowID {
                map[n] = i
            }
        }
        return map
    }

    private func present(candidates: [SCWindow], completion: @escaping (CaptureIntent, NSScreen) -> Void) {
        let finish: (CaptureIntent, NSScreen) -> Void = { [weak self] intent, screen in
            // For region capture, keep the dimming overlay up so there's no bright
            // flash between selecting and the annotation layer appearing; the caller
            // calls dismiss() once the annotation overlay is in place. Other intents
            // dismiss immediately.
            if case .region = intent {
                completion(intent, screen)
            } else {
                self?.dismiss()
                completion(intent, screen)
            }
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

        // Trigger a highlight at the current mouse position right away, so the user
        // doesn't have to move the mouse first.
        let mouse = NSEvent.mouseLocation
        for win in windows where win.frame.contains(mouse) {
            (win.contentView as? SelectionView)?.updateHoverFromGlobalMouse()
        }
    }

    /// Tear down the selection overlay. Called automatically for cancel/window/full-screen;
    /// for region capture the annotation controller calls this when editing ends.
    func dismiss() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        for win in windows { win.orderOut(nil) }
        windows.removeAll()
    }

    /// Keep the overlay windows visible (they keep dimming the screen behind the
    /// annotation layer) but stop handling keys, so the annotation layer owns all input.
    func freeze() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
    }

    /// Move the committed cut-out (the bright hole in the dim overlay) to a new rect.
    /// Called by the annotation layer's move tool so the hole tracks the screenshot block.
    func updateCutout(_ rectLocal: NSRect, on screen: NSScreen) {
        for win in windows where win.frame.origin == screen.frame.origin {
            (win.contentView as? SelectionView)?.setCommittedCutout(rectLocal)
        }
    }

    /// Temporarily hide the overlay windows (e.g. while a Save panel is up) without
    /// tearing them down.
    func hide() {
        for win in windows { win.orderOut(nil) }
    }

    /// Re-show the overlay windows after `hide()`.
    func unhide() {
        for win in windows { win.orderFrontRegardless() }
    }

    private func screenUnderCursor() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

// MARK: - Selection window

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

// MARK: - Selection view

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
    private var committed = false   // frozen after an intent is sent; stops repaint flicker

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
        guard !committed else { return }
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(origin: startPoint!, size: .zero)
        didDrag = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !committed, let start = startPoint else { return }
        // Clamp the cursor to this screen's bounds. During a drag, events keep coming to
        // the window where the drag began even after the pointer crosses onto another
        // screen; without clamping, the selection would extend past this display and the
        // crop (computed against this one display) would be out-of-bounds → the capture
        // came out distorted and missing the other screen's pixels. Cross-screen capture
        // is intentionally not supported; the selection stays within the start screen.
        let raw = convert(event.locationInWindow, from: nil)
        let p = NSPoint(
            x: min(max(raw.x, bounds.minX), bounds.maxX),
            y: min(max(raw.y, bounds.minY), bounds.maxY)
        )
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
        guard !committed else { return }
        if didDrag, let rect = currentRect, rect.width > 4, rect.height > 4 {
            committed = true
            // Redraw NOW into the committed state (cut-out kept bright, but our own
            // border dropped) and flush synchronously, so the live-drag border is gone
            // before the annotation layer draws its single border on top. Otherwise the
            // two borders briefly overlap at slightly different widths and the edge
            // appears to jitter.
            needsDisplay = true
            displayIfNeeded()
            onLocalIntent?(.region(rect))
            return
        }
        // Capture window: re-hit-test at the actual click point rather than relying on
        // the cached hover (which only updates on mouseMoved and can be stale/nil,
        // causing the "sometimes snaps, sometimes doesn't" behavior).
        let clickPoint = convert(event.locationInWindow, from: nil)
        if let (win, _) = topmostWindow(atLocal: clickPoint) {
            committed = true
            onLocalIntent?(.window(win))
            return
        }
        // Nothing selected: reset for another attempt.
        startPoint = nil
        currentRect = nil
        didDrag = false
        needsDisplay = true
    }

    func updateHoverFromGlobalMouse() {
        guard let win = window else { return }
        let global = NSEvent.mouseLocation
        let local = convert(win.convertPoint(fromScreen: global), from: nil)
        updateHover(at: local)
    }

    /// Reposition the committed cut-out (used when the move tool pans the capture).
    func setCommittedCutout(_ rect: NSRect) {
        currentRect = rect
        needsDisplay = true
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

    /// Find the topmost SCWindow under `localPoint` (in this view's local coordinates).
    /// Returns (SCWindow, local rect).
    private func topmostWindow(atLocal localPoint: NSPoint) -> (SCWindow, NSRect)? {
        guard let win = window else { return nil }
        let globalPoint = win.convertPoint(toScreen: localPoint)
        let primary = Self.primaryScreen()
        let cgPoint = CGPoint(x: globalPoint.x, y: primary.frame.maxY - globalPoint.y)
        // `candidates` was sorted into true front-to-back z-order in begin(), so the first
        // window that contains the point is the frontmost one actually visible there. This
        // correctly ignores windows occluded at that point (a window in front contains it
        // too and comes first), instead of snapping to some hidden window behind.
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

    /// The screen whose origin is the CG coordinate origin (NSScreen frame.origin == .zero).
    private static func primaryScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        // After commit, KEEP the cut-out open (selected region stays bright) but draw no
        // border/label/hint. The annotation layer is placed on top and paints the
        // screenshot + the single border into the same region. Because the region stays
        // bright throughout, there's no dark frame and thus no jitter during hand-off.
        if committed {
            if let rect = currentRect {
                NSColor.clear.setFill()
                rect.fill(using: .copy)
            }
            return
        }

        drawHint()

        // Region selection takes priority.
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

        // Window highlight.
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
