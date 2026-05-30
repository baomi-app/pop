import AppKit
import ScreenCaptureKit
import CoreGraphics
import Carbon.HIToolbox

/// Unified capture selection overlay (covers every screen).
///
/// The screen is FROZEN: on the hotkey we grab each display with CGDisplayCreateImage and
/// show it dimmed. The grab matches the display's tone-mapping (no gray) and runs before we
/// take focus (transient UI like Spotlight stays in the shot). The overlay is a
/// non-activating panel, so it takes keyboard without activating the app — forcing
/// activation flashed the screen on both show and dismiss.
///
/// KNOWN UNSOLVED: on a Liquid Retina XDR (HDR/EDR) display, the capture itself makes the
/// display briefly drop EDR headroom — a flash on show. Confirmed it's the capture (no
/// capture = no flash; every capture API flashes). macOS's own *continuous* screen
/// recording doesn't flash, so the lead is a kept-alive SCStream you read frames from
/// (never a one-shot grab, never stop mid-session) — untested here; loose ends are the
/// HDR→CGImage colour (to avoid a gray wash) and a possible flash when the stream stops.
/// - Hover: highlight the window under the cursor
/// - Click: capture the hit window (cropped from the frozen snapshot)
/// - Drag: region capture
/// - Return / Enter: full screen (the screen under the cursor)
/// - Esc: cancel
enum CaptureIntent {
    /// Region selection: cropped image + where it sat on screen (for in-place editing).
    case region(image: CGImage, rectGlobal: CGRect)
    /// Window / full-screen grab that goes straight to finalize (no editing step).
    case direct(image: CGImage)
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

        // Start the continuous screen stream capture asynchronously, and only present
        // the overlays once we have the clean, frozen snapshots for all screens!
        Task { [weak self] in
            do {
                var shots: [CGDirectDisplayID: CGImage] = [:]
                let screens = NSScreen.screens
                
                try await ScreenStreamCapturer.shared.start(on: screens) { [weak self] displayID, cgImage in
                    guard let self else { return }
                    
                    // Collect the snapshot for this screen
                    shots[displayID] = cgImage
                    
                    // Once we have frames for all active screens, present the overlay!
                    if shots.count == screens.count {
                        self.present(shots: shots, completion: completion)
                    }
                }
            } catch {
                NSLog("[Pop] Failed to start screen stream capture: \(error)")
                completion(.cancel, NSScreen.main ?? NSScreen.screens[0])
            }
        }

        // The window list (hover highlight + click-to-capture-window) needs
        // SCShareableContent, which is async-only; load it in the background and inject it.
        Task { [weak self] in
            let content = try? await ScreenCaptureService.shareableContent()
            let myBundle = Bundle.main.bundleIdentifier
            var candidates: [SCWindow] = []
            if let content {
                let filtered = content.windows.filter { win in
                    win.isOnScreen
                        && win.owningApplication != nil
                        && win.owningApplication?.bundleIdentifier != myBundle
                        && win.windowLayer == 0          // Regular app windows only (exclude Dock, wallpaper, menus)
                        && win.frame.width > 40 && win.frame.height > 40
                }
                // SCShareableContent.windows is NOT reliably in z-order, so a hotkey-raised
                // (but unfocused) window could rank behind others and fail to snap. Re-sort by
                // the true front-to-back order from the window server.
                let zIndex = Self.zOrderIndex()
                candidates = filtered.sorted {
                    (zIndex[$0.windowID] ?? Int.max) < (zIndex[$1.windowID] ?? Int.max)
                }
            }
            await MainActor.run { self?.updateCandidates(candidates) }
        }
    }

    /// Inject the window list into the already-visible overlay (loads a moment after the
    /// synchronous freeze).
    private func updateCandidates(_ candidates: [SCWindow]) {
        for win in windows {
            (win.contentView as? SelectionView)?.setCandidates(candidates)
        }
    }

    /// The frozen still for the given screen.
    private func snapshot(for screen: NSScreen) -> CGImage? {
        for win in windows where win.displayID == screen.displayID {
            return (win.contentView as? SelectionView)?.snapshotImage
        }
        return nil
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

    private func present(shots: [CGDirectDisplayID: CGImage],
                         completion: @escaping (CaptureIntent, NSScreen) -> Void) {
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

        // Windows open dimming the LIVE screen (snapshot nil); applyFreeze() swaps the
        // frozen still in once the behind-the-dim capture lands.
        for screen in NSScreen.screens {
            let win = SelectionWindow(screen: screen, candidates: [], snapshot: shots[screen.displayID])
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
                // Full screen also opens the in-place annotation editor (rect = the whole
                // screen under the cursor), matching region and window capture.
                let screen = self.screenUnderCursor()
                if let img = self.snapshot(for: screen) {
                    finish(.region(image: img, rectGlobal: screen.frame), screen)
                } else {
                    finish(.cancel, screen)   // capture not landed yet
                }
                return nil
            default:
                return event
            }
        }

        // Show the frozen overlay windows (at .screenSaver level, covering every display)
        // and force each to draw its still before it appears, so the first composited frame
        // is already the dimmed freeze.
        for win in windows {
            win.orderFrontRegardless()
            win.contentView?.display()
        }
        // Non-activating panel: make it key for keyboard input. This is a far gentler
        // focus change than NSApp.activate(ignoringOtherApps:), which caused the
        // window-server flash on both show and dismiss.
        windows.first?.makeKey()

        // Highlight the window under the cursor right away, without needing a mouse move.
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

        // Stop stream capture after dismissal (deferred by 800ms to hide stop-capture visual drop / indicator fadeout)
        ScreenStreamCapturer.shared.stopDeferred()
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

final class SelectionWindow: NSPanel {
    var onIntent: ((CaptureIntent) -> Void)?
    let displayID: CGDirectDisplayID

    func updateSnapshot(_ newSnapshot: CGImage) {
        (contentView as? SelectionView)?.updateSnapshot(newSnapshot)
    }

    init(screen: NSScreen, candidates: [SCWindow], snapshot: CGImage?) {
        self.displayID = screen.displayID
        super.init(
            contentRect: screen.frame,
            // .nonactivatingPanel lets the overlay become key and receive keyboard
            // (Esc / Return) WITHOUT activating the app. Forcing activation
            // (NSApp.activate(ignoringOtherApps:)) caused a window-server transition that
            // flashed the screen on both show and dismiss; a non-activating panel avoids it.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Transparent: the overlay dims the live screen (and later the frozen still drawn on
        // top), so it must let the screen show through where it isn't painted.
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = false
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        setFrame(screen.frame, display: true)

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                 candidates: candidates,
                                 snapshot: snapshot)
        view.onLocalIntent = { [weak self] localIntent in
            guard let self else { return }
            switch localIntent {
            case .region(let image, let rectLocal):
                self.onIntent?(.region(image: image, rectGlobal: self.convertToScreen(rectLocal)))
            case .direct(let image):
                self.onIntent?(.direct(image: image))
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
    case region(image: CGImage, rectLocal: NSRect)
    case direct(image: CGImage)
    case cancel
}

final class SelectionView: NSView {
    fileprivate var onLocalIntent: ((LocalIntent) -> Void)?

    private var candidates: [SCWindow]
    private var snapshot: CGImage?      // frozen full-screen image (native px), for cropping
    private var nsSnapshot: NSImage?    // same, for drawing

    private var startPoint: NSPoint?
    private var currentRect: NSRect?
    private var didDrag = false
    private var hoveredWindow: SCWindow?
    private var hoveredLocalRect: NSRect?
    private var trackingArea: NSTrackingArea?
    private var committed = false   // frozen after an intent is sent; stops repaint flicker

    func updateSnapshot(_ newSnapshot: CGImage) {
        self.snapshot = newSnapshot
        self.nsSnapshot = NSImage(cgImage: newSnapshot, size: bounds.size)
        needsDisplay = true
    }

    init(frame: NSRect, candidates: [SCWindow], snapshot: CGImage?) {
        self.candidates = candidates
        self.snapshot = snapshot
        self.nsSnapshot = snapshot.map { NSImage(cgImage: $0, size: frame.size) }
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The frozen still for this display (used for full-screen capture via Return).
    var snapshotImage: CGImage? { snapshot }

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
            // If the behind-the-dim capture hasn't landed yet (snapshot nil), there's
            // nothing to crop — leave the selection uncommitted so the user can release
            // again a moment later. (The capture lands well within human reaction time.)
            guard let img = crop(rect) else { return }
            committed = true
            // Redraw NOW into the committed state (cut-out kept bright, but our own
            // border dropped) and flush synchronously, so the live-drag border is gone
            // before the annotation layer draws its single border on top. Otherwise the
            // two borders briefly overlap at slightly different widths and the edge
            // appears to jitter.
            needsDisplay = true
            displayIfNeeded()
            onLocalIntent?(.region(image: img, rectLocal: rect))
            return
        }
        // Capture window: re-hit-test at the actual click point rather than relying on
        // the cached hover (which only updates on mouseMoved and can be stale/nil,
        // causing the "sometimes snaps, sometimes doesn't" behavior).
        let clickPoint = convert(event.locationInWindow, from: nil)
        if let (_, localRect) = topmostWindow(atLocal: clickPoint) {
            let rect = localRect.intersection(bounds)
            guard !rect.isNull, !rect.isEmpty, let img = crop(rect) else { return }
            committed = true
            currentRect = rect          // keep this block bright in the committed backdrop
            needsDisplay = true
            displayIfNeeded()
            // Window capture opens the same in-place annotation editor as region, anchored
            // at the window's frame — so it can be marked up before copy/save.
            onLocalIntent?(.region(image: img, rectLocal: rect))
            return
        }
        // Nothing selected: reset for another attempt.
        startPoint = nil
        currentRect = nil
        didDrag = false
        needsDisplay = true
    }

    /// Crop a local (bottom-left origin, points) rect out of the frozen snapshot,
    /// returning native-pixel image content.
    private func crop(_ localRect: NSRect) -> CGImage? {
        guard let snap = snapshot, bounds.width > 0, bounds.height > 0 else { return nil }
        let sx = CGFloat(snap.width) / bounds.width
        let sy = CGFloat(snap.height) / bounds.height
        let px = CGRect(
            x: localRect.minX * sx,
            y: (bounds.height - localRect.maxY) * sy,   // points bottom-left → pixels top-left
            width: localRect.width * sx,
            height: localRect.height * sy
        ).integral
        return snap.cropping(to: px)
    }

    /// Receive the window list once it has loaded (the freeze is shown before it's ready).
    func setCandidates(_ c: [SCWindow]) {
        candidates = c
        // Light up the window under the cursor now that we know the windows.
        if !didDrag, startPoint == nil { updateHoverFromGlobalMouse() }
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
        // Frozen base image (if the snapshot failed, fall back to a transparent live view).
        nsSnapshot?.draw(in: bounds)
        // Dim everything on top of the base.
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        // After commit, KEEP the cut-out bright (selected region) but draw no
        // border/label/hint. The annotation layer is placed on top and paints the
        // screenshot + the single border into the same region. Because the region stays
        // bright throughout, there's no dark frame and thus no jitter during hand-off.
        if committed {
            if let rect = currentRect { revealBright(rect) }
            return
        }

        drawHint()

        // Region selection takes priority.
        if let rect = currentRect, didDrag {
            revealBright(rect)

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
            revealBright(clipped)

            let border = NSBezierPath(rect: clipped)
            border.lineWidth = 3
            NSColor(calibratedRed: 1.0, green: 0.823, blue: 0.290, alpha: 1).setStroke()
            border.stroke()
        }
    }

    /// Restore the frozen image at full brightness within `rect` (undoing the dim there).
    /// Falls back to punching a transparent hole (live screen) when no snapshot exists.
    private func revealBright(_ rect: NSRect) {
        guard let img = nsSnapshot else {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            return
        }
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        img.draw(in: bounds)
        NSGraphicsContext.current?.restoreGraphicsState()
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
