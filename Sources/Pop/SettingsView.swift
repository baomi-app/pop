import SwiftUI
import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Preferences pane (macOS System Settings style).
struct SettingsView: View {
    @ObservedObject var store: HotkeyStore = .shared
    @State private var recording = false
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var launchErrorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("截图") {
                    HStack(spacing: 8) {
                        KeyRecorderView(config: $store.config, recording: $recording)
                            .frame(width: 180, height: 24)
                        Button("默认") { store.config = .default }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("快捷键")
            } footer: {
                Text("点击编辑框，按下你想要的组合键。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("保存到本地", isOn: $store.saveEnabled)
                LabeledContent("目录") {
                    HStack(spacing: 8) {
                        Text(store.savePath?.path ?? String(localized: "未选择"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(store.savePath == nil ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Button("选择…") { pickDirectory() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
                .disabled(!store.saveEnabled)
            } header: {
                Text("保存")
            } footer: {
                Text("默认不保存。开启后每次截图都会按所选目录保存为 PNG。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("截图完成后显示", isOn: $store.toastEnabled)
            } header: {
                Text("完成提示")
            } footer: {
                Text("截图完成后短暂显示「\(Brand.Copy.saved)」。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("开机启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        toggleLaunchAtLogin(to: newValue)
                    }
                if let msg = launchErrorMessage {
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("登录项")
            } footer: {
                Text("登录时自动在后台启动 Pop。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 480)
        .onAppear {
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func toggleLaunchAtLogin(to enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchErrorMessage = nil
        } catch {
            NSLog("[Pop] Toggle launch-at-login failed: \(error)")
            launchErrorMessage = String(localized: "切换失败，请到系统设置 › 通用 › 登录项中手动启用。")
            // Roll back to match the real system state.
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "选择")
        if let cur = store.savePath { panel.directoryURL = cur }
        if panel.runModal() == .OK, let url = panel.url {
            store.savePath = url
        }
    }
}

// MARK: - Key recorder

struct KeyRecorderView: NSViewRepresentable {
    @Binding var config: HotkeyConfig
    @Binding var recording: Bool

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onCapture = { keyCode, mods in
            config = HotkeyConfig(keyCode: keyCode, modifierFlags: mods)
            recording = false
        }
        v.onRecordingChange = { recording = $0 }
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.display = config.displayString
        v.isRecording = recording
        v.needsDisplay = true
    }
}

final class RecorderView: NSView {
    var onCapture: ((UInt32, NSEvent.ModifierFlags) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    var display: String = "" { didSet { needsDisplay = true } }
    var isRecording: Bool = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        onRecordingChange?(true)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }

        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            onRecordingChange?(false)
            return
        }

        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard !mods.isEmpty else { return }

        onCapture?(UInt32(event.keyCode), mods)
        isRecording = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 6
        let bg = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        (isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.16)
            : NSColor.textBackgroundColor).setFill()
        bg.fill()

        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                  xRadius: radius, yRadius: radius)
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        border.lineWidth = 1
        border.stroke()

        let text = (isRecording ? String(localized: "按下组合键…（⎋ 取消）") : display) as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attrs)
        let p = NSPoint(x: (bounds.width - size.width) / 2,
                        y: (bounds.height - size.height) / 2)
        text.draw(at: p, withAttributes: attrs)
    }
}

// MARK: - Window presentation

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if let win = window {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = String(localized: "Pop 偏好设置")
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = NSHostingView(rootView: SettingsView())
        win.delegate = SettingsWindowObserver.shared
        SettingsWindowObserver.shared.onClose = { [weak self] in
            self?.window = nil
            NSApp.setActivationPolicy(.accessory)
        }
        self.window = win

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

private final class SettingsWindowObserver: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowObserver()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}
