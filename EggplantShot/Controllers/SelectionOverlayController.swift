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

    /// Snapshot of app windows taken before overlays cover the screen.
    private var windowHitTester = WindowHitTester.snapshot()
    /// Window frame under the cursor while idle (Cocoa global coords).
    private var hoveredWindowRect: CGRect?
    /// On mouse-down over a window: wait to see if this is a click-lock or a free drag.
    private var pendingWindowPick: (start: CGPoint, frame: CGRect)?

    private let handleVisualSize: CGFloat = 8
    private let handleHitSize: CGFloat = 12
    private let minSelection: CGFloat = 2
    /// Movement past this distance abandons window pick and starts free drag.
    private let windowPickDragThreshold: CGFloat = 4

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
        // Capture window list before our dimmed panels cover everything.
        windowHitTester = WindowHitTester.snapshot()
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
        updateHoverHighlight(at: mouse)
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
        hoveredWindowRect = nil
        pendingWindowPick = nil
        phase = .idle
    }

    private func installMonitors() {
        removeMonitors()

        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
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
        case .mouseMoved:
            handleMouseMoved(at: point)
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

    private func handleMouseMoved(at point: CGPoint) {
        guard phase == .idle, pendingWindowPick == nil else { return }
        updateHoverHighlight(at: point)
    }

    private func updateHoverHighlight(at point: CGPoint) {
        let frame = windowHitTester.windowFrame(at: point)
        hoveredWindowRect = frame
        if let frame {
            currentRect = frame
        } else {
            currentRect = .null
        }
        updateHighlight(showHandles: false)
    }

    private func lockWindowSelection(_ frame: CGRect) {
        pendingWindowPick = nil
        hoveredWindowRect = nil
        currentRect = frame
        phase = .refining
        updateHighlight(showHandles: true)
        showToolbar()
    }

    private func beginFreeDraw(from start: CGPoint) {
        pendingWindowPick = nil
        hoveredWindowRect = nil
        phase = .drawing
        dragKind = .draw(start: start)
        currentRect = CGRect(origin: start, size: .zero)
        updateHighlight(showHandles: false)
    }

    private func handleMouseDown(at point: CGPoint) {
        switch phase {
        case .idle:
            if let frame = hoveredWindowRect ?? windowHitTester.windowFrame(at: point) {
                // Defer lock until mouse-up so a drag can still start free selection.
                pendingWindowPick = (start: point, frame: frame)
                currentRect = frame
                updateHighlight(showHandles: false)
            } else {
                beginFreeDraw(from: point)
            }

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
                // Start a new rough selection (or window pick again).
                toolbar?.close()
                toolbar = nil
                phase = .idle
                dragKind = nil
                if let frame = windowHitTester.windowFrame(at: point) {
                    pendingWindowPick = (start: point, frame: frame)
                    hoveredWindowRect = frame
                    currentRect = frame
                    updateHighlight(showHandles: false)
                } else {
                    beginFreeDraw(from: point)
                }
            }
        }
    }

    private func handleMouseDragged(at point: CGPoint) {
        if let pending = pendingWindowPick {
            let dx = point.x - pending.start.x
            let dy = point.y - pending.start.y
            if hypot(dx, dy) >= windowPickDragThreshold {
                beginFreeDraw(from: pending.start)
                // Fall through with draw drag using the original start.
            } else {
                return
            }
        }

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
        defer {
            dragKind = nil
            pendingWindowPick = nil
        }

        if let pending = pendingWindowPick, phase == .idle {
            lockWindowSelection(pending.frame)
            return
        }

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
                updateHoverHighlight(at: point)
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
        content.layer?.backgroundColor = NSColor.white.cgColor
        content.layer?.cornerRadius = 6
        content.layer?.masksToBounds = false
        content.layer?.shadowColor = NSColor.black.cgColor
        content.layer?.shadowOpacity = 0.18
        content.layer?.shadowRadius = 8
        content.layer?.shadowOffset = CGSize(width: 0, height: -1)

        // Snipaste-like icon groups (annotate stubs | edit stubs | confirm actions).
        let annotate: [(String, String)] = [
            ("rectangle", "Shape"),
            ("arrow.up.right", "Arrow"),
            ("pencil", "Pen"),
            ("paintbrush.pointed", "Marker"),
            ("square.grid.3x3", "Mosaic"),
            ("textformat", "Text"),
            ("1.circle", "Step"),
            ("magnifyingglass", "Magnifier"),
            ("eraser", "Eraser"),
        ]
        let edit: [(String, String)] = [
            ("doc.text.viewfinder", "OCR"),
            ("arrow.uturn.backward", "Undo"),
            ("arrow.uturn.forward", "Redo"),
        ]

        let annotateViews: [NSView] = annotate.map { symbol, tip in
            iconButton(systemName: symbol, tooltip: tip, enabled: false, action: nil)
        }
        let editViews: [NSView] = edit.map { symbol, tip in
            iconButton(systemName: symbol, tooltip: tip, enabled: false, action: nil)
        }

        let cancel = iconButton(systemName: "xmark", tooltip: "Cancel", enabled: true, action: #selector(cancelTapped))
        let pin = iconButton(systemName: "pin.fill", tooltip: "Pin", enabled: true, action: #selector(pinTapped))
        let save = iconButton(systemName: "square.and.arrow.down", tooltip: "Save", enabled: false, action: nil)
        let copy = iconButton(systemName: "doc.on.doc", tooltip: "Copy", enabled: true, action: #selector(copyTapped))
        let more = iconButton(systemName: "ellipsis", tooltip: "More", enabled: false, action: nil)

        let primary = primaryAction == .pin ? pin : copy
        primary.keyEquivalent = "\r"

        let actionViews: [NSView] = [cancel, pin, save, copy, more]

        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

        for v in annotateViews { stack.addArrangedSubview(v) }
        stack.addArrangedSubview(divider())
        for v in editViews { stack.addArrangedSubview(v) }
        stack.addArrangedSubview(divider())
        for v in actionViews { stack.addArrangedSubview(v) }

        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let fitting = stack.fittingSize
        let size = CGSize(width: max(fitting.width, 280), height: max(fitting.height, 28))
        content.frame = CGRect(origin: .zero, size: size)

        panel.setContentSize(size)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false // custom layer shadow on the pill
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = content
        panel.defaultButtonCell = primary.cell as? NSButtonCell
    }

    private func iconButton(
        systemName: String,
        tooltip: String,
        enabled: Bool,
        action: Selector?
    ) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        button.bezelStyle = .inline
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.isEnabled = enabled
        button.target = action == nil ? nil : self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])

        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        button.image = image
        button.contentTintColor = enabled
            ? NSColor(calibratedWhite: 0.22, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
        return button
    }

    private func divider() -> NSView {
        let wrap = NSView(frame: .zero)
        wrap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrap.widthAnchor.constraint(equalToConstant: 7),
            wrap.heightAnchor.constraint(equalToConstant: 24),
        ])
        let line = NSView(frame: .zero)
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 14),
            line.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        return wrap
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
        let gap: CGFloat = 4
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(selection) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }

        // Prefer below the selection, right-aligned to the selection’s trailing edge.
        var origin = CGPoint(
            x: selection.maxX - size.width,
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
    override var isOpaque: Bool { false }
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
        acceptsMouseMovedEvents = true
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
        border.lineWidth = 1.5
        accent.setStroke()
        border.stroke()

        if showHandles {
            drawHandles()
        }

        let w = Int(selectionRect.width.rounded())
        let h = Int(selectionRect.height.rounded())
        let label = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        var labelOrigin = CGPoint(
            x: selectionRect.minX,
            y: selectionRect.maxY + 8
        )
        if labelOrigin.y + size.height + 4 > bounds.maxY {
            labelOrigin.y = selectionRect.minY - size.height - 8
        }
        let bg = CGRect(origin: labelOrigin, size: size).insetBy(dx: -6, dy: -3)
        NSColor.black.withAlphaComponent(0.72).setFill()
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
            NSBezierPath(ovalIn: r).fill()
            accent.setStroke()
            let stroke = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            stroke.lineWidth = 1.5
            stroke.stroke()
        }
    }
}
