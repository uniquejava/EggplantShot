import AppKit

/// Brief centered toast (volume-HUD style). Does not activate the app.
@MainActor
enum StatusHUD {
    private static var panel: NSPanel?
    private static var hideWork: DispatchWorkItem?

    static func show(_ message: String) {
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.sizeToFit()

        let padX: CGFloat = 22
        let padY: CGFloat = 14
        let contentSize = NSSize(
            width: max(160, ceil(label.frame.width) + padX * 2),
            height: ceil(label.frame.height) + padY * 2
        )
        label.frame = NSRect(
            x: padX,
            y: padY,
            width: contentSize.width - padX * 2,
            height: contentSize.height - padY * 2
        )

        let chrome = NSView(frame: NSRect(origin: .zero, size: contentSize))
        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        chrome.layer?.cornerRadius = 12
        chrome.layer?.cornerCurve = .continuous
        chrome.addSubview(label)

        let tip = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tip.isOpaque = false
        tip.backgroundColor = .clear
        tip.hasShadow = true
        tip.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        tip.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        tip.hidesOnDeactivate = false
        tip.isReleasedWhenClosed = false
        tip.ignoresMouseEvents = true
        tip.contentView = chrome
        tip.alphaValue = 0

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        if let screen {
            let frame = screen.frame
            tip.setFrameOrigin(NSPoint(
                x: frame.midX - contentSize.width / 2,
                y: frame.midY - contentSize.height / 2
            ))
        }
        tip.orderFrontRegardless()
        panel = tip

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            tip.animator().alphaValue = 1
        }

        let work = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                panel?.animator().alphaValue = 0
            }, completionHandler: {
                panel?.orderOut(nil)
                panel?.close()
                panel = nil
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: work)
    }
}
