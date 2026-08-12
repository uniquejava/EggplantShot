import AppKit
import Foundation

/// A single global hotkey binding (key + modifiers).
struct HotkeyBinding: Equatable, Hashable, Codable {
    var keyCode: UInt16
    var modifiers: UInt

    var nsModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
            .intersection([.command, .option, .control, .shift])
    }

    var displayName: String {
        HotkeyBinding.describe(keyCode: keyCode, modifiers: nsModifiers)
    }

    static func describe(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 49: return "Space"
        case 36: return "↩"
        case 53: return "Esc"
        default:
            return "Key\(keyCode)"
        }
    }

    /// HIToolbox virtual key codes.
    static let f1: UInt16 = 122
    static let f3: UInt16 = 99
}

enum HotkeyAction: String, CaseIterable, Codable {
    case snip
    case snipAndCopy
    case hideShowImages
}

@MainActor
final class HotkeySettings: ObservableObject {
    private static let disabledKey = "hotkeysDisabled"

    @Published var hotkeysDisabled: Bool {
        didSet { UserDefaults.standard.set(hotkeysDisabled, forKey: Self.disabledKey) }
    }

    /// Fixed MVP bindings (Snipaste defaults).
    let snip = HotkeyBinding(keyCode: HotkeyBinding.f1, modifiers: 0)
    let snipAndCopy = HotkeyBinding(keyCode: HotkeyBinding.f1, modifiers: NSEvent.ModifierFlags.command.rawValue)
    let hideShowImages = HotkeyBinding(keyCode: HotkeyBinding.f3, modifiers: NSEvent.ModifierFlags.shift.rawValue)

    init() {
        hotkeysDisabled = UserDefaults.standard.bool(forKey: Self.disabledKey)
    }

    func binding(for action: HotkeyAction) -> HotkeyBinding {
        switch action {
        case .snip: return snip
        case .snipAndCopy: return snipAndCopy
        case .hideShowImages: return hideShowImages
        }
    }
}
