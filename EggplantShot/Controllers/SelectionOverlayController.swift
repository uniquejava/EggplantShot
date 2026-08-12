import AppKit

/// Full-screen dimmed overlay for drag-selecting a capture region.
@MainActor
final class SelectionOverlayController {
    enum Outcome {
        case cancelled
        case selected(CGRect)
    }

    private var panels: [SelectionPanel] = []
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var dragStart: CGPoint?
    private var currentRect: CGRect = .null
    private var eventMonitors: [Any] = []

    var isActive: Bool { continuation != nil }

    func beginSelection() async -> Outcome {
        if continuation != nil {
            cancel()
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            showOverlays()
        }
    }

    func cancel() {
        tearDownOverlays()
        finish(.cancelled)
    }

    private func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(returning: outcome)
    }

    private func showOverlays() {
        tearDownOverlays()
        for screen in NSScreen.screens {
            let panel = SelectionPanel(screen: screen)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        // Prefer the screen under the cursor for key focus (Esc).
        let mouse = NSEvent.mouseLocation
        if let panel = panels.first(where: { NSMouseInRect(mouse, $0.screenFrame, false) }) ?? panels.first {
            panel.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        installMonitors()
    }

    private func tearDownOverlays() {
        removeMonitors()
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        dragStart = nil
        currentRect = .null
    }

    private func installMonitors() {
        removeMonitors()

        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let mon = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            self?.handleMouse(event)
            return nil
        }) {
            eventMonitors.append(mon)
        }

        if let mon = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            self?.handleMouse(event)
        }) {
            eventMonitors.append(mon)
        }

        if let mon = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if event.keyCode == 53 {
                self?.tearDownOverlays()
                self?.finish(.cancelled)
                return nil
            }
            return event
        }) {
            eventMonitors.append(mon)
        }
    }

    private func removeMonitors() {
        for m in eventMonitors {
            NSEvent.removeMonitor(m)
        }
        eventMonitors.removeAll()
    }

    private func handleMouse(_ event: NSEvent) {
        // Always use global Cocoa coordinates.
        let point = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            dragStart = point
            currentRect = CGRect(origin: point, size: .zero)
            updateHighlight()

        case .leftMouseDragged:
            guard let start = dragStart else { return }
            currentRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            updateHighlight()

        case .leftMouseUp:
            guard let start = dragStart else { return }
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            tearDownOverlays()
            if rect.width < 2 || rect.height < 2 {
                finish(.cancelled)
            } else {
                finish(.selected(rect))
            }

        default:
            break
        }
    }

    private func updateHighlight() {
        for panel in panels {
            panel.setSelection(currentRect)
        }
    }
}

private final class SelectionPanel: NSPanel {
    let screenFrame: CGRect
    private let overlayView: SelectionOverlayNSView

    init(screen: NSScreen) {
        self.screenFrame = screen.frame
        self.overlayView = SelectionOverlayNSView(frame: CGRect(origin: .zero, size: screen.frame.size))

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = overlayView
    }

    func setSelection(_ globalRect: CGRect) {
        let local = CGRect(
            x: globalRect.origin.x - screenFrame.origin.x,
            y: globalRect.origin.y - screenFrame.origin.y,
            width: globalRect.width,
            height: globalRect.height
        )
        overlayView.selectionRect = local
        overlayView.needsDisplay = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayNSView: NSView {
    var selectionRect: CGRect = .null

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        guard !selectionRect.isNull, selectionRect.width > 0, selectionRect.height > 0 else { return }

        NSGraphicsContext.current?.compositingOperation = .clear
        selectionRect.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor.white.setStroke()
        border.stroke()

        let w = Int(selectionRect.width.rounded())
        let h = Int(selectionRect.height.rounded())
        let label = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        var labelOrigin = CGPoint(
            x: selectionRect.midX - size.width / 2,
            y: selectionRect.minY - size.height - 6
        )
        if labelOrigin.y < 4 {
            labelOrigin.y = selectionRect.maxY + 6
        }
        let bg = CGRect(origin: labelOrigin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        label.draw(at: labelOrigin, withAttributes: attrs)
    }
}
