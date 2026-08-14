import AppKit

final class RefineToolbarTooltip {
    private static let showDelay: TimeInterval = 0.35
    private static let padX: CGFloat = 7
    private static let padY: CGFloat = 4
    private static let gap: CGFloat = 6

    private var texts: [ObjectIdentifier: String] = [:]
    private var showWorkItem: DispatchWorkItem?
    private weak var anchor: NSView?
    private var panel: NSPanel?
    private let label = NSTextField(labelWithString: "")

    init() {
        label.font = .systemFont(ofSize: 11)
        label.textColor = NSColor(calibratedWhite: 0.15, alpha: 1)
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.lineBreakMode = .byClipping
    }

    /// Opt a control into the custom tooltip (clears native `toolTip`).
    func register(_ view: NSView, text: String) {
        texts[ObjectIdentifier(view)] = text
        view.toolTip = nil
    }

    func handleHover(_ button: NSButton?) {
        cancelPending()
        guard let button, let text = texts[ObjectIdentifier(button)] else {
            hide()
            return
        }
        if anchor === button, panel?.isVisible == true { return }
        hide()
        anchor = button
        let work = DispatchWorkItem { [weak self] in
            self?.show(text: text, relativeTo: button)
        }
        showWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    func hide() {
        cancelPending()
        anchor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func cancelPending() {
        showWorkItem?.cancel()
        showWorkItem = nil
    }

    private func show(text: String, relativeTo view: NSView) {
        guard let host = view.window else { return }
        label.stringValue = text
        label.sizeToFit()
        let contentSize = NSSize(
            width: ceil(label.frame.width) + Self.padX * 2,
            height: ceil(label.frame.height) + Self.padY * 2
        )

        let tip = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tip.isOpaque = false
        tip.backgroundColor = .clear
        tip.hasShadow = true
        tip.level = NSWindow.Level(rawValue: host.level.rawValue + 1)
        tip.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        tip.hidesOnDeactivate = false
        tip.isReleasedWhenClosed = false
        tip.ignoresMouseEvents = true

        let chrome = NSView(frame: NSRect(origin: .zero, size: contentSize))
        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = NSColor.white.cgColor
        chrome.layer?.cornerRadius = 4
        chrome.layer?.borderWidth = 0.5
        chrome.layer?.borderColor = NSColor(calibratedWhite: 0.75, alpha: 1).cgColor
        label.frame = NSRect(
            x: Self.padX,
            y: Self.padY,
            width: contentSize.width - Self.padX * 2,
            height: contentSize.height - Self.padY * 2
        )
        chrome.addSubview(label)
        tip.contentView = chrome

        let buttonScreen = view.convert(view.bounds, to: nil)
        let screenRect = host.convertToScreen(buttonScreen)
        var origin = CGPoint(
            x: screenRect.midX - contentSize.width / 2,
            y: screenRect.minY - contentSize.height - Self.gap
        )
        if let screen = host.screen ?? NSScreen.main {
            if origin.y < screen.visibleFrame.minY + 2 {
                origin.y = screenRect.maxY + Self.gap
            }
            origin.x = min(
                max(origin.x, screen.visibleFrame.minX + 2),
                screen.visibleFrame.maxX - contentSize.width - 2
            )
        }
        tip.setFrameOrigin(origin)
        tip.orderFrontRegardless()
        panel = tip
    }
}

