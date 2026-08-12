import AppKit
import Foundation

/// Listens for multiple global hotkey bindings via a CGEvent tap.
final class HotkeyMonitor: @unchecked Sendable {
    var onAction: ((HotkeyAction) -> Void)?

    private var bindings: [HotkeyAction: HotkeyBinding] = [:]
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPaused = false
    private let lock = NSLock()

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eventTap != nil
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        isPaused = paused
        lock.unlock()
    }

    func updateBindings(_ map: [HotkeyAction: HotkeyBinding]) {
        lock.lock()
        bindings = map
        lock.unlock()
    }

    func start() {
        stop()
        guard AXIsProcessTrusted() else {
            NSLog("EggplantShot: event tap skipped — Accessibility not trusted")
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            NSLog("EggplantShot: failed to create event tap — grant Accessibility permission")
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func restart() {
        DispatchQueue.main.async { [weak self] in
            self?.start()
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let paused = isPaused
        let current = bindings
        lock.unlock()

        guard !paused else {
            return Unmanaged.passUnretained(event)
        }

        let pressedCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let currentMods = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            .intersection([.command, .option, .control, .shift])

        for (action, binding) in current {
            guard pressedCode == binding.keyCode else { continue }
            if currentMods == binding.nsModifiers {
                fire(action)
                // Swallow F-keys so macOS doesn't also trigger system actions when possible.
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func fire(_ action: HotkeyAction) {
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(action)
        }
    }
}
