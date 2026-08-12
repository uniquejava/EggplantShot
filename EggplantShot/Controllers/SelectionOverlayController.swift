import AppKit

/// Full-screen dimmed overlay: drag a region, then refine (handles + toolbar) before capture.
@MainActor
final class SelectionOverlayController {
    enum ConfirmAction {
        case pin
        case copy
    }

    enum Outcome {
        case cancelled
        case confirmed(CGRect, action: ConfirmAction)
    }

    private enum Phase {
        case idle
        case drawing
        case refining
    }

    private enum DragKind {
        case draw(start: CGPoint)
        case move(startRect: CGRect, startPoint: CGPoint)
        case resize(handle: Handle, startRect: CGRect, startPoint: CGPoint)
    }

    private enum Handle: CaseIterable {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }

    private var panels: [SelectionPanel] = []
    private var toolbar: RefineToolbarController?
    private var continuation: CheckedContinuation<Outcome, Never>?
    private var phase: Phase = .idle
    private var dragKind: DragKind?
    private var currentRect: CGRect = .null
    private var primaryAction: ConfirmAction = .pin
    private var eventMonitors: [Any] = []

    private let handleVisualSize: CGFloat = 8
    private let handleHitSize: CGFloat = 12
    private let minSelection: CGFloat = 2

    var isActive: Bool { continuation != nil }

    func beginSelection(primaryAction: ConfirmAction = .pin) async -> Outcome {
        if continuation != nil {
            cancel()
        }
        self.primaryAction = primaryAction

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.phase = .idle
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
        phase = .idle
        continuation.resume(returning: outcome)
    }

    private func confirm(_ action: ConfirmAction) {
        guard !currentRect.isNull,
              currentRect.width >= minSelection,
              currentRect.height >= minSelection
        else {
            tearDownOverlays()
            finish(.cancelled)
            return
        }
        let rect = currentRect
        tearDownOverlays()
        finish(.confirmed(rect, action: action))
    }

    private func showOverlays() {
        tearDownOverlays()
        for screen in NSScreen.screens {
            let panel = SelectionPanel(screen: screen)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        if let panel = panels.first(where: { NSMouseInRect(mouse, $0.screenFrame, false) }) ?? panels.first {
            panel.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        installMonitors()
    }

    private func tearDownOverlays() {
        removeMonitors()
        toolbar?.close()
        toolbar = nil
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        panels.removeAll()
        dragKind = nil
        currentRect = .null
        phase = .idle
    }

    private func installMonitors() {
        removeMonitors()

        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let mon = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            guard let self else { return event }
            // Pass through so the floating toolbar can receive clicks.
            if let toolbar = self.toolbar, toolbar.containsGlobalPoint(NSEvent.mouseLocation) {
                return event
            }
            self.handleMouse(event)
            return nil
        }) {
            eventMonitors.append(mon)
        }

        if let mon = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            guard let self else { return }
            if let toolbar = self.toolbar, toolbar.containsGlobalPoint(NSEvent.mouseLocation) {
                return
            }
            self.handleMouse(event)
        }) {
            eventMonitors.append(mon)
        }

        if let mon = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                self.tearDownOverlays()
                self.finish(.cancelled)
                return nil
            }
            // Return / keypad Enter confirms primary action while refining.
            if self.phase == .refining, event.keyCode == 36 || event.keyCode == 76 {
                self.confirm(self.primaryAction)
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
        let point = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            handleMouseDown(at: point)
        case .leftMouseDragged:
            handleMouseDragged(at: point)
        case .leftMouseUp:
            handleMouseUp(at: point)
        default:
            break
        }
    }

    private func handleMouseDown(at point: CGPoint) {
        switch phase {
        case .idle:
            phase = .drawing
            dragKind = .draw(start: point)
            currentRect = CGRect(origin: point, size: .zero)
            updateHighlight(showHandles: false)

        case .drawing:
            dragKind = .draw(start: point)
            currentRect = CGRect(origin: point, size: .zero)
            updateHighlight(showHandles: false)

        case .refining:
            if let handle = hitTestHandle(at: point) {
                dragKind = .resize(handle: handle, startRect: currentRect, startPoint: point)
            } else if currentRect.contains(point) {
                dragKind = .move(startRect: currentRect, startPoint: point)
            } else {
                // Start a new rough selection.
                phase = .drawing
                dragKind = .draw(start: point)
                currentRect = CGRect(origin: point, size: .zero)
                toolbar?.close()
                toolbar = nil
                updateHighlight(showHandles: false)
            }
        }
    }

    private func handleMouseDragged(at point: CGPoint) {
        guard let dragKind else { return }

        switch dragKind {
        case .draw(let start):
            currentRect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            updateHighlight(showHandles: false)

        case .move(let startRect, let startPoint):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            currentRect = startRect.offsetBy(dx: dx, dy: dy)
            clampRectToScreens()
            updateHighlight(showHandles: true)
            repositionToolbar()

        case .resize(let handle, let startRect, let startPoint):
            currentRect = resizedRect(handle: handle, startRect: startRect, startPoint: startPoint, point: point)
            updateHighlight(showHandles: true)
            repositionToolbar()
        }
    }

    private func handleMouseUp(at point: CGPoint) {
        defer { dragKind = nil }

        switch phase {
        case .idle:
            break

        case .drawing:
            guard case .draw(let start) = dragKind else { return }
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            if rect.width < minSelection || rect.height < minSelection {
                currentRect = .null
                phase = .idle
                updateHighlight(showHandles: false)
                return
            }
            currentRect = rect
            phase = .refining
            updateHighlight(showHandles: true)
            showToolbar()

        case .refining:
            updateHighlight(showHandles: true)
            repositionToolbar()
        }
    }

    // MARK: - Geometry

    private func hitTestHandle(at point: CGPoint) -> Handle? {
        for handle in Handle.allCases {
            if handleHitRect(handle, in: currentRect).contains(point) {
                return handle
            }
        }
        return nil
    }

    private func handleCenter(_ handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.minY)
        }
    }

    private func handleHitRect(_ handle: Handle, in rect: CGRect) -> CGRect {
        let c = handleCenter(handle, in: rect)
        return CGRect(
            x: c.x - handleHitSize / 2,
            y: c.y - handleHitSize / 2,
            width: handleHitSize,
            height: handleHitSize
        )
    }

    private func resizedRect(
        handle: Handle,
        startRect: CGRect,
        startPoint: CGPoint,
        point: CGPoint
    ) -> CGRect {
        var minX = startRect.minX
        var maxX = startRect.maxX
        var minY = startRect.minY
        var maxY = startRect.maxY
        let dx = point.x - startPoint.x
        let dy = point.y - startPoint.y

        switch handle {
        case .topLeft:
            minX += dx
            maxY += dy
        case .top:
            maxY += dy
        case .topRight:
            maxX += dx
            maxY += dy
        case .left:
            minX += dx
        case .right:
            maxX += dx
        case .bottomLeft:
            minX += dx
            minY += dy
        case .bottom:
            minY += dy
        case .bottomRight:
            maxX += dx
            minY += dy
        }

        if minX > maxX { swap(&minX, &maxX) }
        if minY > maxY { swap(&minY, &maxY) }

        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if rect.width < minSelection { rect.size.width = minSelection }
        if rect.height < minSelection { rect.size.height = minSelection }
        return rect
    }

    private func clampRectToScreens() {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(currentRect)
        }) ?? NSScreen.main else { return }

        var r = currentRect
        r.origin.x = min(max(r.origin.x, screen.frame.minX), screen.frame.maxX - r.width)
        r.origin.y = min(max(r.origin.y, screen.frame.minY), screen.frame.maxY - r.height)
        currentRect = r
    }

    // MARK: - Drawing / toolbar

    private func updateHighlight(showHandles: Bool) {
        for panel in panels {
            panel.setSelection(
                currentRect,
                showHandles: showHandles,
                handleVisualSize: handleVisualSize
            )
        }
    }

    private func showToolbar() {
        toolbar?.close()
        let bar = RefineToolbarController(primaryAction: primaryAction) { [weak self] action in
            guard let self else { return }
            switch action {
            case .pin:
                self.confirm(.pin)
            case .copy:
                self.confirm(.copy)
            case .cancel:
                self.tearDownOverlays()
                self.finish(.cancelled)
            }
        }
        toolbar = bar
        repositionToolbar()
        bar.orderFront()
    }

    private func repositionToolbar() {
        guard let toolbar, !currentRect.isNull else { return }
        toolbar.reposition(around: currentRect)
        // Dragging on the full-screen overlay can raise it above the toolbar;
        // keep the bar strictly in front after every move/resize.
        toolbar.orderFront()
    }
}

// MARK: - Toolbar

@MainActor
private final class RefineToolbarController: NSObject {
    enum Action {
        case pin
        case copy
        case cancel
    }

    private let panel: NSPanel
    private let onAction: (Action) -> Void

    init(primaryAction: SelectionOverlayController.ConfirmAction, onAction: @escaping (Action) -> Void) {
        self.onAction = onAction
        self.panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let content = RefineToolbarView(frame: .zero)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        content.layer?.cornerRadius = 8
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.separatorColor.cgColor

        let pin = NSButton(title: "Pin", target: self, action: #selector(pinTapped))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        for button in [pin, copy, cancel] {
            button.bezelStyle = .rounded
            button.setButtonType(.momentaryPushIn)
            button.controlSize = .small
        }

        let primary = primaryAction == .pin ? pin : copy
        primary.keyEquivalent = "\r"

        let stack = NSStackView(views: [pin, copy, cancel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let fitting = stack.fittingSize
        let size = CGSize(width: max(fitting.width, 200), height: max(fitting.height, 36))
        content.frame = CGRect(origin: .zero, size: size)

        panel.setContentSize(size)
        // Above SelectionPanel (.screenSaver) so resize/move never buries the bar under the dim mask.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = content
        panel.defaultButtonCell = primary.cell as? NSButtonCell
    }

    @objc private func pinTapped() { onAction(.pin) }
    @objc private func copyTapped() { onAction(.copy) }
    @objc private func cancelTapped() { onAction(.cancel) }

    func orderFront() {
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    func containsGlobalPoint(_ point: CGPoint) -> Bool {
        panel.frame.contains(point)
    }

    func reposition(around selection: CGRect) {
        let size = panel.frame.size
        let gap: CGFloat = 10
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(selection) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        // Prefer below the selection; flip above if near the bottom.
        var origin = CGPoint(
            x: selection.midX - size.width / 2,
            y: selection.minY - size.height - gap
        )
        if origin.y < screen.frame.minY + 4 {
            origin.y = selection.maxY + gap
        }

        origin.x = min(max(origin.x, screen.frame.minX + 4), screen.frame.maxX - size.width - 4)
        origin.y = min(max(origin.y, screen.frame.minY + 4), screen.frame.maxY - size.height - 4)

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }
}

private final class RefineToolbarView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Overlay panels

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

    func setSelection(_ globalRect: CGRect, showHandles: Bool, handleVisualSize: CGFloat) {
        let local: CGRect
        if globalRect.isNull {
            local = .null
        } else {
            local = CGRect(
                x: globalRect.origin.x - screenFrame.origin.x,
                y: globalRect.origin.y - screenFrame.origin.y,
                width: globalRect.width,
                height: globalRect.height
            )
        }
        overlayView.selectionRect = local
        overlayView.showHandles = showHandles
        overlayView.handleVisualSize = handleVisualSize
        overlayView.needsDisplay = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayNSView: NSView {
    var selectionRect: CGRect = .null
    var showHandles = false
    var handleVisualSize: CGFloat = 8

    private let accent = NSColor.systemBlue

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
        border.lineWidth = 2
        accent.setStroke()
        border.stroke()

        if showHandles {
            drawHandles()
        }

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
            y: selectionRect.maxY + 6
        )
        if labelOrigin.y + size.height + 4 > bounds.maxY {
            labelOrigin.y = selectionRect.minY - size.height - 6
        }
        let bg = CGRect(origin: labelOrigin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        label.draw(at: labelOrigin, withAttributes: attrs)
    }

    private func drawHandles() {
        let centers: [CGPoint] = [
            CGPoint(x: selectionRect.minX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.midX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.maxY),
            CGPoint(x: selectionRect.minX, y: selectionRect.midY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.midY),
            CGPoint(x: selectionRect.minX, y: selectionRect.minY),
            CGPoint(x: selectionRect.midX, y: selectionRect.minY),
            CGPoint(x: selectionRect.maxX, y: selectionRect.minY),
        ]
        let s = handleVisualSize
        for c in centers {
            let r = CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s)
            NSColor.white.setFill()
            NSBezierPath(rect: r).fill()
            accent.setStroke()
            let stroke = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
            stroke.lineWidth = 1
            stroke.stroke()
        }
    }
}
