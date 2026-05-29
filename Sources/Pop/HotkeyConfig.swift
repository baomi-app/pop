import AppKit
import Carbon.HIToolbox

/// Global hotkey config (keyCode + modifiers), persisted to UserDefaults.
struct HotkeyConfig: Equatable {
    var keyCode: UInt32
    var modifierFlags: NSEvent.ModifierFlags

    static let `default` = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_X),
        modifierFlags: [.command, .shift]
    )

    /// Convert to Carbon modifiers.
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifierFlags.contains(.command) { m |= UInt32(cmdKey) }
        if modifierFlags.contains(.shift)   { m |= UInt32(shiftKey) }
        if modifierFlags.contains(.option)  { m |= UInt32(optionKey) }
        if modifierFlags.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    /// Human-readable form, e.g. ⌘⇧X.
    var displayString: String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option)  { s += "⌥" }
        if modifierFlags.contains(.shift)   { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }
        s += KeyCodeNames.name(for: keyCode)
        return s
    }
}

/// Singleton store that publishes changes.
/// Holds: global hotkey / save-to-disk toggle and path / toast toggle.
/// The toast TEXT is not user-editable — it comes from Brand.Copy.saved and follows the
/// app locale.
@MainActor
final class HotkeyStore: ObservableObject {
    static let shared = HotkeyStore()

    private let keyKey = "Pop.Hotkey.keyCode"
    private let modKey = "Pop.Hotkey.modifierFlags"
    private let saveEnabledKey = "Pop.Save.enabled"
    private let savePathKey = "Pop.Save.path"
    private let toastEnabledKey = "Pop.Toast.enabled"

    @Published var config: HotkeyConfig { didSet { saveHotkey() } }
    @Published var saveEnabled: Bool { didSet { UserDefaults.standard.set(saveEnabled, forKey: saveEnabledKey) } }
    @Published var savePath: URL? { didSet { UserDefaults.standard.set(savePath?.path, forKey: savePathKey) } }
    @Published var toastEnabled: Bool { didSet { UserDefaults.standard.set(toastEnabled, forKey: toastEnabledKey) } }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: keyKey) != nil {
            let k = UInt32(d.integer(forKey: keyKey))
            let m = NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: modKey)))
            self.config = HotkeyConfig(keyCode: k, modifierFlags: m)
        } else {
            self.config = .default
        }
        self.saveEnabled = d.object(forKey: saveEnabledKey) as? Bool ?? false
        if let p = d.string(forKey: savePathKey), !p.isEmpty {
            self.savePath = URL(fileURLWithPath: p)
        } else {
            self.savePath = nil
        }
        self.toastEnabled = d.object(forKey: toastEnabledKey) as? Bool ?? true
    }

    private func saveHotkey() {
        let d = UserDefaults.standard
        d.set(Int(config.keyCode), forKey: keyKey)
        d.set(Int(config.modifierFlags.rawValue), forKey: modKey)
    }
}

/// keyCode → display name mapping (covers common keys; anything missing falls back to "Key N").
enum KeyCodeNames {
    static func name(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space:  return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_Tab:    return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default: return "Key \(keyCode)"
        }
    }
}
