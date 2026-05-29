import SwiftUI
import AppKit

/// The "pop" feedback: a corn-yellow capsule appears at the bottom-center of the
/// screen, lingers briefly, then fades out.
@MainActor
enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String) {
        panel?.close()

        let hosting = NSHostingView(rootView: ToastView(text: text))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.contentView = hosting

        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let size = hosting.fittingSize
            p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 96))
        }
        p.alphaValue = 0
        p.orderFrontRegardless()
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            p.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                p.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    p.close()
                    if panel === p { panel = nil }
                }
            })
        }
    }
}

private struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Brand.charcoal)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Capsule().fill(Brand.cornYellow))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .fixedSize()
    }
}
