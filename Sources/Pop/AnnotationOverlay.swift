import AppKit
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Carbon.HIToolbox

// MARK: - Pixelate (mosaic)

enum Pixelator {
    static func pixelate(_ cg: CGImage, blockScale: CGFloat = 18) -> CGImage? {
        let ci = CIImage(cgImage: cg)
        let f = CIFilter.pixellate()
        f.inputImage = ci
        f.scale = Float(blockScale)
        guard let out = f.outputImage else { return nil }
        return CIContext().createCGImage(out, from: ci.extent)
    }
}

// MARK: - Toolbar model

/// Shared state between the SwiftUI toolbar and the AppKit canvas.
@MainActor
final class OverlayModel: ObservableObject {
    @Published var tool: AnnoKind = .move   // default to move, so a fresh capture can be repositioned right away
    @Published var color: Color = Palette.red
    @Published var lineWidth: CGFloat = 4

    // Wired by the controller to the canvas / completion logic.
    var onUndo: () -> Void = {}
    var onClear: () -> Void = {}
    var onCopy: () -> Void = {}
    var onSave: () -> Void = {}
    var onCancel: () -> Void = {}
}

// MARK: - Toolbar (SwiftUI)

struct AnnotationToolbar: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(AnnoKind.allCases) { kind in toolButton(kind) }
            }
            Divider().frame(height: 20)
            HStack(spacing: 5) {
                ForEach(Palette.all.indices, id: \.self) { i in
                    let c = Palette.all[i]
                    Circle()
                        .fill(c)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.white.opacity(model.color == c ? 0.95 : 0.2),
                                                       lineWidth: model.color == c ? 2.5 : 1))
                        .onTapGesture { model.color = c }
                }
            }
            Divider().frame(height: 20)
            HStack(spacing: 2) {
                ForEach([3.0, 5.0, 9.0], id: \.self) { w in
                    Button {
                        model.lineWidth = w
                    } label: {
                        Circle().fill(Color.white.opacity(model.lineWidth == w ? 1 : 0.45))
                            .frame(width: CGFloat(w) + 4, height: CGFloat(w) + 4)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(model.lineWidth == w ? Color.white.opacity(0.14) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().frame(height: 20)
            Button(action: model.onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "撤销"))
            Button(action: model.onClear) {
                Image(systemName: "trash")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "清空"))
            Divider().frame(height: 20)
            Button(action: model.onCancel) {
                Image(systemName: "xmark")
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "取消"))
            Button(action: model.onSave) {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "保存…"))
            Button(action: model.onCopy) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(Brand.charcoal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Brand.cornYellow))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(String(localized: "复制"))
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.16)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    private func toolButton(_ kind: AnnoKind) -> some View {
        Button {
            model.tool = kind
        } label: {
            Image(systemName: kind.symbol)
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(model.tool == kind ? Brand.cornYellow : Color.clear))
                .foregroundStyle(model.tool == kind ? Brand.charcoal : Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
        .help(kind.label)
    }
}

// MARK: - Shared renderer (preview == export)

/// Draws the frozen base image + annotations into the current (non-flipped)
/// NSGraphicsContext. Used by both on-screen preview and bitmap export, so what
/// you see is what gets saved.
enum AnnotationRenderer {
    static func P(_ n: CGPoint, _ r: CGRect) -> CGPoint {
        CGPoint(x: r.minX + n.x * r.width, y: r.maxY - n.y * r.height)   // n.y is top-origin
    }

    static func rectOf(_ a: CGPoint, _ b: CGPoint, _ r: CGRect) -> CGRect {
        let pa = P(a, r), pb = P(b, r)
        return CGRect(x: min(pa.x, pb.x), y: min(pa.y, pb.y),
                      width: abs(pb.x - pa.x), height: abs(pb.y - pa.y))
    }

    static func draw(base: NSImage, pixelated: NSImage?,
                     annotations: [Annotation], draft: Annotation?,
                     into rect: CGRect, lineScale: CGFloat) {
        base.draw(in: rect)
        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        for a in annotations { drawOne(a, rect: rect, lineScale: lineScale, pixelated: pixelated) }
        if let d = draft { drawOne(d, rect: rect, lineScale: lineScale, pixelated: pixelated) }
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private static func drawOne(_ a: Annotation, rect: CGRect, lineScale: CGFloat, pixelated: NSImage?) {
        let color = NSColor(a.color)
        let lw = max(a.lineWidth * lineScale, 1)
        color.set()

        switch a.kind {
        case .move:
            break   // not a drawable annotation; the move tool only pans the capture

        case .line:
            let path = NSBezierPath()
            path.move(to: P(a.start, rect)); path.line(to: P(a.end, rect))
            path.lineWidth = lw; path.lineCapStyle = .round; path.stroke()

        case .arrow:
            let s = P(a.start, rect), e = P(a.end, rect)
            let shaft = NSBezierPath()
            shaft.move(to: s); shaft.line(to: e)
            shaft.lineWidth = lw; shaft.lineCapStyle = .round; shaft.stroke()
            let ang = atan2(e.y - s.y, e.x - s.x)
            let head = max(lw * 3.2, 10 * lineScale)
            let l = CGPoint(x: e.x - head * cos(ang - .pi / 7), y: e.y - head * sin(ang - .pi / 7))
            let r = CGPoint(x: e.x - head * cos(ang + .pi / 7), y: e.y - head * sin(ang + .pi / 7))
            let ah = NSBezierPath()
            ah.move(to: l); ah.line(to: e); ah.line(to: r)
            ah.lineWidth = lw; ah.lineCapStyle = .round; ah.lineJoinStyle = .round; ah.stroke()

        case .rect:
            let p = NSBezierPath(roundedRect: rectOf(a.start, a.end, rect),
                                 xRadius: 4 * lineScale, yRadius: 4 * lineScale)
            p.lineWidth = lw; p.stroke()

        case .ellipse:
            let p = NSBezierPath(ovalIn: rectOf(a.start, a.end, rect))
            p.lineWidth = lw; p.stroke()

        case .pen:
            guard a.points.count > 1 else { return }
            let p = NSBezierPath()
            p.move(to: P(a.points[0], rect))
            for pt in a.points.dropFirst() { p.line(to: P(pt, rect)) }
            p.lineWidth = lw; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()

        case .text:
            guard !a.text.isEmpty else { return }
            let fontSize = max(a.fontSize * lineScale, 8)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: color
            ]
            let ns = a.text as NSString
            let size = ns.size(withAttributes: attrs)
            let top = P(a.start, rect)
            ns.draw(at: NSPoint(x: top.x, y: top.y - size.height), withAttributes: attrs)

        case .blur:
            guard let pix = pixelated else { return }
            let br = rectOf(a.start, a.end, rect)
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: br).addClip()
            pix.draw(in: rect)
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }
}

// MARK: - Canvas view (AppKit, non-flipped)

final class AnnotationCanvasView: NSView {
    private let baseCG: CGImage
    private let baseImage: NSImage
    private let pixelImage: NSImage?
    private var selRect: CGRect          // selection rect in this view's local coords (mutable: move tool pans it)
    private let lineScaleExport: CGFloat // pixel / point

    private(set) var annotations: [Annotation] = []
    private var draft: Annotation?
    private weak var model: OverlayModel?

    private var textField: NSTextField?
    private var pendingText: Annotation?

    /// Drag anchor while the move tool pans the whole capture.
    private var movePrev: CGPoint?
    /// Called when the move tool shifts the selection, so the dimming overlay underneath
    /// can move its cut-out to stay aligned with the screenshot block.
    var onSelRectChanged: ((CGRect) -> Void)?
    /// Called once a move gesture ends, so the toolbar can re-anchor to the new position.
    /// (It deliberately stays still during the drag.)
    var onMoveEnded: ((CGRect) -> Void)?

    init(baseCG: CGImage, selRect: CGRect, exportScale: CGFloat, model: OverlayModel) {
        self.baseCG = baseCG
        self.selRect = selRect
        self.lineScaleExport = exportScale
        self.baseImage = NSImage(cgImage: baseCG, size: selRect.size)
        if let px = Pixelator.pixelate(baseCG) {
            self.pixelImage = NSImage(cgImage: px, size: selRect.size)
        } else {
            self.pixelImage = nil
        }
        self.model = model
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func resetCursorRects() {
        addCursorRect(selRect, cursor: .crosshair)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let hit = super.hitTest(point) {
            return hit
        }
        // If it hit a transparent area (returning nil), consume the hit to prevent click-through
        return self
    }

    // MARK: Editing API (wired to toolbar)

    func undo() {
        if textField != nil { cancelText(); return }
        if draft != nil { draft = nil } else if !annotations.isEmpty { annotations.removeLast() }
        needsDisplay = true
    }

    func clearAll() {
        cancelText()
        draft = nil
        annotations.removeAll()
        needsDisplay = true
    }

    /// Composite base + annotations into a CGImage at native resolution.
    func flatten() -> CGImage? {
        commitText()
        let pxW = baseCG.width, pxH = baseCG.height
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: pxW, height: pxH)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let full = CGRect(x: 0, y: 0, width: pxW, height: pxH)
        AnnotationRenderer.draw(base: baseImage, pixelated: pixelImage,
                                annotations: annotations, draft: nil,
                                into: full, lineScale: lineScaleExport)
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Draw the standard 0.28 dimming backdrop over the entire screen.
        // This ensures the background area has alpha 0.28 (completely solid to macOS
        // Window Server hit-testing), preventing all click-through deactivations, while
        // the selected rect is painted bright on top by AnnotationRenderer.
        NSColor.black.withAlphaComponent(0.28).set()
        bounds.fill()

        AnnotationRenderer.draw(base: baseImage, pixelated: pixelImage,
                                annotations: annotations, draft: draft,
                                into: selRect, lineScale: 1)
        let border = NSBezierPath(rect: selRect)
        border.lineWidth = 1.5
        NSColor(Brand.cornYellow).setStroke()
        border.stroke()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard selRect.contains(p) else { return }
        if textField != nil { commitText(); return }

        let tool = model?.tool ?? .rect
        if tool == .move {
            movePrev = p
            return
        }
        if tool == .text {
            beginText(at: p)
            return
        }
        var a = newAnnotation(at: norm(p))
        if tool == .pen { a.points = [a.start] }
        draft = a
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        if model?.tool == .move {
            guard let prev = movePrev else { return }
            let p = convert(event.locationInWindow, from: nil)
            selRect.origin.x += p.x - prev.x
            selRect.origin.y += p.y - prev.y
            movePrev = p
            onSelRectChanged?(selRect)
            needsDisplay = true
            return
        }
        guard draft != nil else { return }
        let p = norm(convert(event.locationInWindow, from: nil))
        if model?.tool == .pen {
            draft?.points.append(p)
        } else {
            draft?.end = p
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if movePrev != nil {
            movePrev = nil
            onMoveEnded?(selRect)   // move finished: let the toolbar re-anchor
        }
        guard let d = draft else { return }
        draft = nil
        if d.isMeaningful { annotations.append(d) }
        needsDisplay = true
    }

    // MARK: Text tool

    private func beginText(at p: CGPoint) {
        let tf = NSTextField(frame: NSRect(x: p.x, y: p.y - 24, width: 200, height: 24))
        tf.placeholderString = String(localized: "输入文字")
        tf.font = .systemFont(ofSize: 15, weight: .semibold)
        tf.textColor = NSColor(model?.color ?? Palette.red)
        tf.backgroundColor = NSColor.black.withAlphaComponent(0.5)
        tf.isBordered = false
        tf.focusRingType = .none
        tf.target = self
        tf.action = #selector(textCommitted)
        addSubview(tf)
        window?.makeFirstResponder(tf)
        textField = tf

        var a = newAnnotation(at: norm(CGPoint(x: p.x, y: p.y)))
        a.kind = .text
        pendingText = a
    }

    @objc private func textCommitted() { commitText() }

    private func commitText() {
        guard let tf = textField, var a = pendingText else { return }
        let s = tf.stringValue
        tf.removeFromSuperview()
        textField = nil
        pendingText = nil
        if !s.isEmpty {
            a.text = s
            a.color = model?.color ?? a.color
            annotations.append(a)
        }
        needsDisplay = true
    }

    private func cancelText() {
        textField?.removeFromSuperview()
        textField = nil
        pendingText = nil
    }

    // MARK: Helpers

    private func newAnnotation(at start: CGPoint) -> Annotation {
        let lw = model?.lineWidth ?? 4
        let c = model?.color ?? Palette.red
        return Annotation(kind: model?.tool ?? .rect, color: c, lineWidth: lw,
                          fontSize: max(lw * 4.5, 18), start: start, end: start)
    }

    /// View point → normalized [0,1] within the selection, top-origin.
    private func norm(_ p: CGPoint) -> CGPoint {
        let nx = (p.x - selRect.minX) / selRect.width
        let ny = (selRect.maxY - p.y) / selRect.height
        return CGPoint(x: min(max(nx, 0), 1), y: min(max(ny, 0), 1))
    }
}

// MARK: - Overlay window

/// A non-activating panel: it takes keyboard (annotation shortcuts, text-tool typing)
/// without activating the app. Forcing activation flashed the screen on show/dismiss.
final class AnnotationOverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Controller

/// Presents the in-place annotation overlay over a screen, with the captured region
/// frozen at its original position. No separate editor window, no activation-policy
/// toggling — the app stays a menu-bar accessory throughout.
@MainActor
final class AnnotationOverlayController {
    static let shared = AnnotationOverlayController()

    private var window: AnnotationOverlayWindow?
    private var canvas: AnnotationCanvasView?
    private var keyMonitor: Any?
    private var savePanelUp = false

    /// - base: captured region image (native pixels)
    /// - rectGlobal: selection rect in global screen coords (bottom-left origin)
    /// - screen: the screen the selection is on
    func present(base: CGImage, rectGlobal: CGRect, screen: NSScreen) {
        // Clear only a stale annotation window from a prior run — NOT the selection
        // overlay, which was just set up by this same capture flow and must stay
        // underneath to keep dimming/freezing the screen behind us. (dismiss() would
        // tear that selection overlay down, leaving the toolbar floating over a live,
        // un-frozen desktop.)
        teardownAnnotation()

        let model = OverlayModel()
        let selLocal = CGRect(
            x: rectGlobal.minX - screen.frame.minX,
            y: rectGlobal.minY - screen.frame.minY,
            width: rectGlobal.width, height: rectGlobal.height
        )

        // Derive pixel/point scale from the captured image itself, so it's correct
        // regardless of which screen this is.
        let exportScale = selLocal.width > 0 ? CGFloat(base.width) / selLocal.width
                                             : screen.backingScaleFactor

        let canvas = AnnotationCanvasView(baseCG: base, selRect: selLocal,
                                          exportScale: exportScale, model: model)
        canvas.frame = NSRect(origin: .zero, size: screen.frame.size)

        // Wire toolbar actions.
        model.onUndo = { [weak canvas] in canvas?.undo() }
        model.onClear = { [weak canvas] in canvas?.clearAll() }
        model.onCancel = { [weak self] in self?.dismiss() }
        model.onCopy = { [weak self, weak canvas] in
            guard let img = canvas?.flatten() else { return }
            CaptureCoordinator.finalize(img)
            self?.dismiss()
        }
        model.onSave = { [weak self, weak canvas] in
            guard let img = canvas?.flatten() else { return }
            self?.runSavePanel(img)
        }

        // When the move tool pans the capture, keep the dimming hole underneath aligned.
        canvas.onSelRectChanged = { rect in
            RegionSelectionController.shared.updateCutout(rect, on: screen)
        }

        let win = AnnotationOverlayWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = NSColor.black.withAlphaComponent(0.001)
        win.level = .screenSaver
        win.hidesOnDeactivate = false
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        win.setFrame(screen.frame, display: true)

        // Toolbar as a SwiftUI subview, positioned just under (or above) the selection.
        let toolbar = NSHostingView(rootView: AnnotationToolbar(model: model))
        toolbar.frame.size = toolbar.fittingSize
        let tbW = toolbar.fittingSize.width, tbH = toolbar.fittingSize.height
        var tbX = selLocal.midX - tbW / 2
        tbX = min(max(tbX, 8), screen.frame.width - tbW - 8)
        var tbY = selLocal.minY - tbH - 10                  // below selection
        if tbY < 8 {
            tbY = selLocal.maxY + 10                        // try above selection
            if tbY > screen.frame.height - tbH - 50 {       // if top goes into the notch/menu bar, place at the bottom inside selection
                tbY = 40
            }
        }
        toolbar.frame = NSRect(x: tbX, y: tbY, width: tbW, height: tbH)
        canvas.addSubview(toolbar)

        // After a move ends, glide the toolbar to the capture's new position (below if
        // there's room, otherwise above; clamped on-screen). It stays put during the drag.
        canvas.onMoveEnded = { [weak toolbar] rect in
            guard let toolbar else { return }
            var x = rect.midX - tbW / 2
            x = min(max(x, 8), screen.frame.width - tbW - 8)
            var y = rect.minY - tbH - 10
            if y < 8 {
                y = rect.maxY + 10
                if y > screen.frame.height - tbH - 50 {
                    y = 40
                }
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.allowsImplicitAnimation = true
                toolbar.animator().frame = NSRect(x: x, y: y, width: tbW, height: tbH)
            }
        }

        win.contentView = canvas
        self.window = win
        self.canvas = canvas

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak model] event in
            // While the Save panel is up, let it handle keys (Esc cancels the panel,
            // not our overlay).
            if self?.savePanelUp == true { return event }
            switch Int(event.keyCode) {
            case kVK_Escape:
                self?.dismiss(); return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                // Return = copy to clipboard (the common "I'm done, give me the image" key).
                model?.onCopy(); return nil
            case kVK_ANSI_Z where event.modifierFlags.contains(.command):
                model?.onUndo(); return nil
            case kVK_ANSI_C where event.modifierFlags.contains(.command):
                model?.onCopy(); return nil
            case kVK_ANSI_S where event.modifierFlags.contains(.command):
                model?.onSave(); return nil
            default:
                return event
            }
        }

        // Non-activating panel: take key without activating the app (no flash).
        win.orderFrontRegardless()
        win.makeKey()
        // Do NOT dismiss the selection overlay. It stays underneath to keep providing
        // the dimming; we only stop it from handling keys so the annotation layer owns
        // all input. Both layers are torn down together in dismiss().
        RegionSelectionController.shared.freeze()
    }

    private func runSavePanel(_ cgImage: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Pop-\(Self.timestamp()).png"
        if let dir = HotkeyStore.shared.savePath { panel.directoryURL = dir }
        panel.canCreateDirectories = true

        // Hide the overlay so it doesn't cover the panel (our window sits at
        // .screenSaver level, above panels).
        // Hide both overlays so neither covers/dims the Save panel.
        savePanelUp = true
        window?.orderOut(nil)
        RegionSelectionController.shared.hide()
        NSApp.activate(ignoringOtherApps: true)

        let response = panel.runModal()
        savePanelUp = false

        guard response == .OK, let url = panel.url else {
            // Cancelled: bring both overlays back so the user can keep editing.
            RegionSelectionController.shared.unhide()
            window?.makeKeyAndOrderFront(nil)
            return
        }
        do {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try data.write(to: url)
            // Also put it on the clipboard and give the "pop" feedback, matching finalize().
            ClipboardService.copy(cgImage)
            if HotkeyStore.shared.toastEnabled {
                Toast.show(Brand.Copy.saved)
            }
        } catch {
            NSLog("[Pop] Save failed: \(error)")
        }
        dismiss()
    }

    private func dismiss() {
        teardownAnnotation()
        // Tear down the selection overlay that stayed up underneath.
        RegionSelectionController.shared.dismiss()
    }

    /// Tear down only this controller's own window + key monitor, leaving the selection
    /// overlay (the frozen/dimmed backdrop) untouched.
    private func teardownAnnotation() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        window?.orderOut(nil)
        window = nil
        canvas = nil
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}
