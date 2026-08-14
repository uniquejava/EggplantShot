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

    /// F1–F12 may stand alone; other keys need at least one modifier.
    var isValidAssignable: Bool {
        if Self.isFunctionKey(keyCode) { return true }
        return !nsModifiers.isEmpty
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
        case 48: return "⇥"
        case 51: return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            return keyMap[keyCode] ?? "Key\(keyCode)"
        }
    }

    static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111].contains(keyCode)
    }

    /// HIToolbox virtual key codes.
    static let f1: UInt16 = 122
    static let f3: UInt16 = 99

    private static let keyMap: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
        17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=",
        25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U",
        33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`",
    ]
}

enum HotkeyAction: String, CaseIterable, Codable {
    case snip
    case snipAndCopy
    case hideShowImages

    var settingsTitle: String {
        switch self {
        case .snip: return "Capture"
        case .snipAndCopy: return "Capture and copy"
        case .hideShowImages: return "Hide/Show images"
        }
    }
}

@MainActor
final class HotkeySettings: ObservableObject {
    private static let disabledKey = "hotkeysDisabled"
    private static let bindingsKey = "hotkeyBindings"

    @Published var hotkeysDisabled: Bool {
        didSet { UserDefaults.standard.set(hotkeysDisabled, forKey: Self.disabledKey) }
    }

    @Published private(set) var snip: HotkeyBinding
    @Published private(set) var snipAndCopy: HotkeyBinding
    @Published private(set) var hideShowImages: HotkeyBinding

    static let defaultSnip = HotkeyBinding(keyCode: HotkeyBinding.f1, modifiers: 0)
    static let defaultSnipAndCopy = HotkeyBinding(
        keyCode: HotkeyBinding.f1,
        modifiers: NSEvent.ModifierFlags.command.rawValue
    )
    static let defaultHideShowImages = HotkeyBinding(
        keyCode: HotkeyBinding.f3,
        modifiers: NSEvent.ModifierFlags.shift.rawValue
    )

    init() {
        hotkeysDisabled = UserDefaults.standard.bool(forKey: Self.disabledKey)

        if let data = UserDefaults.standard.data(forKey: Self.bindingsKey),
           let decoded = try? JSONDecoder().decode(StoredBindings.self, from: data) {
            snip = decoded.snip
            snipAndCopy = decoded.snipAndCopy
            hideShowImages = decoded.hideShowImages
        } else {
            snip = Self.defaultSnip
            snipAndCopy = Self.defaultSnipAndCopy
            hideShowImages = Self.defaultHideShowImages
        }
    }

    func binding(for action: HotkeyAction) -> HotkeyBinding {
        switch action {
        case .snip: return snip
        case .snipAndCopy: return snipAndCopy
        case .hideShowImages: return hideShowImages
        }
    }

    /// Assign `binding` to `action`. If another action already uses it, swap.
    func setBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
        guard binding.isValidAssignable else { return }

        if let other = HotkeyAction.allCases.first(where: {
            $0 != action && self.binding(for: $0) == binding
        }) {
            let displaced = self.binding(for: action)
            apply(binding, to: action)
            apply(displaced, to: other)
        } else {
            apply(binding, to: action)
        }
        persistBindings()
    }

    func resetToDefaults() {
        snip = Self.defaultSnip
        snipAndCopy = Self.defaultSnipAndCopy
        hideShowImages = Self.defaultHideShowImages
        persistBindings()
    }

    var allBindings: [HotkeyAction: HotkeyBinding] {
        [
            .snip: snip,
            .snipAndCopy: snipAndCopy,
            .hideShowImages: hideShowImages,
        ]
    }

    private func apply(_ binding: HotkeyBinding, to action: HotkeyAction) {
        switch action {
        case .snip: snip = binding
        case .snipAndCopy: snipAndCopy = binding
        case .hideShowImages: hideShowImages = binding
        }
    }

    private func persistBindings() {
        let stored = StoredBindings(snip: snip, snipAndCopy: snipAndCopy, hideShowImages: hideShowImages)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.bindingsKey)
        }
    }

    private struct StoredBindings: Codable {
        var snip: HotkeyBinding
        var snipAndCopy: HotkeyBinding
        var hideShowImages: HotkeyBinding
    }
}
