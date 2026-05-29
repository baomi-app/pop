import Carbon.HIToolbox
import AppKit

/// 一个轻量的 Carbon 全局快捷键封装。不需要「输入监控」权限。
/// 同时只持有一个热键；重新 register 会替换旧的。
@MainActor
final class CarbonHotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onFire: (() -> Void)?

    private let signature: OSType = OSType(0x504F5043) // 'POPC'
    private let id: UInt32 = 1

    func register(keyCode: UInt32, modifiers: UInt32, onFire: @escaping () -> Void) {
        unregister()
        self.onFire = onFire

        installHandlerIfNeeded()

        var hkID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("[Pop] 注册全局快捷键失败：status=\(status)")
        }
        _ = hkID
    }

    func unregister() {
        if let r = ref {
            UnregisterEventHotKey(r)
            ref = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
            guard let userData, let eventRef else { return noErr }
            var hkID = EventHotKeyID()
            let s = GetEventParameter(eventRef,
                                      EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID),
                                      nil,
                                      MemoryLayout<EventHotKeyID>.size,
                                      nil,
                                      &hkID)
            if s == noErr {
                let me = Unmanaged<CarbonHotkey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { me.onFire?() }
            }
            return noErr
        }, 1, &spec, ctx, &handler)
    }

    deinit {
        if let r = ref { UnregisterEventHotKey(r) }
        if let h = handler { RemoveEventHandler(h) }
    }
}
