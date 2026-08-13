import AppKit

/// Full-screen dimmed overlay: drag a region, refine, optionally annotate, then capture.
@MainActor
final class SelectionOverlayController {
    enum ConfirmAction {
        case pin
        case copy
        case save
    }

    enum Outcome {
        case cancelled
        /// `image` is the **unannotated** crop from the freeze snapshot.
        /// `document` is the editable annotation state at confirm (pre-bake).
        case confirmed(CGRect, image: NSImage, action: ConfirmAction, document: AnnotationDocument)
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
        /// Outside the selection: opposite edges stay fixed; active edge(s) track the pointer absolutely.
        case expand(handle: Handle, baseRect: CGRect)
        /// Shape or pencil in-progress stroke (tool decides payload).
        case annotateDraw(startLocal: CGPoint)
        case annotateMove(id: UUID, start: Annotation, startPoint: CGPoint)
        case annotateResize(id: UUID, handle: Handle, start: Annotation, startPoint: CGPoint)
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

    /// Shared snip history for `,` / `.` playback (owned by `SnipController`).
    var historyStore: SnipHistoryStore?
    /// Index into `historyStore.records` while browsing; `nil` = not browsing.
    private var historyCursor: Int?
    /// When set, refine/confirm uses this unannotated base instead of cropping the live freeze.
    private var playbackBaseImage: NSImage?

    /// Snapshot of app windows taken before overlays cover the screen.
    private var windowHitTester = WindowHitTester.snapshot()
    /// Per-display freeze frames captured before overlays appear (Snipaste-style).
    private var freezeFrames: [FreezeFrame] = []
    /// Window frame under the cursor while idle (Cocoa global coords).
    private var hoveredWindowRect: CGRect?

    private struct FreezeFrame {
        let screen: NSScreen
        let cgImage: CGImage
    }
    /// On mouse-down over a window: wait to see if this is a click-lock or a free drag.
    private var pendingWindowPick: (start: CGPoint, frame: CGRect)?

    // MARK: Annotation state

    private var annotateTool: AnnotateTool = .none
    private var annotationStyle: AnnotationStyle = AnnotationPrefs.load().style
    /// Sub-toolbar rect / oval switch (next draw + selected mark).
    private var annotationKind: ShapeKind = AnnotationPrefs.load().kind
    private let annotationHistory = AnnotationHistory()
    /// In-progress mark while dragging (selection-local geometry).
    private var draftAnnotation: Annotation?

    private var annotations: [Annotation] { annotationHistory.document.marks }
    private var selectedAnnotationID: UUID? { annotationHistory.document.selectedID }

    private let handleVisualSize: CGFloat = 8
    private let annotationHandleVisualSize: CGFloat = 7
    private let handleHitSize: CGFloat = 12
    /// Border strip + outside octants use this thickness for Snipaste-style resize hit/cursor.
    private let selectionEdgeHit: CGFloat = 8
    private let minSelection: CGFloat = 2
    private let minAnnotation: CGFloat = 4
    /// Freehand sample distance (points). Dense enough to turn freely without
    /// the old rubber-band feel; 120Hz tip polling fills gaps between drag events.
    private let pencilSampleSpacing: CGFloat = 0.15
    /// High-frequency tip polling while stroking.
    private var pencilSampleTimer: Timer?
    /// Movement past this distance abandons window pick and starts free drag.
    private let windowPickDragThreshold: CGFloat = 4
    /// Half-width of the annotation border hit corridor (beyond stroke).
    private let annotationBorderHitSlop: CGFloat = 5

    /// Where the pointer sits relative to annotations while an annotate tool is active.
    private enum AnnotationPointerTarget {
        case handle(id: UUID, handle: Handle)
        case border(id: UUID)
        case draw
        case outside
    }

    var isActive: Bool { continuation != nil }

    func beginSelection(primaryAction: ConfirmAction = .pin) async -> Outcome {
        if continuation != nil {
            cancel()
        }
        self.primaryAction = primaryAction
        historyCursor = nil
        playbackBaseImage = nil

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
        let document = annotationHistory.document
        let image: NSImage?
        if let playback = playbackBaseImage {
            image = Self.baseImageMatchingSelection(playback, size: rect.size)
        } else {
            image = cropFromFreeze(rect)
        }
        guard let image else {
            tearDownOverlays()
            finish(.cancelled)
            return
        }
        tearDownOverlays()
        finish(.confirmed(rect, image: image, action: action, document: document))
    }

    /// Ensures archived / playback base point size matches the confirm selection.
    private static func baseImageMatchingSelection(_ image: NSImage, size: CGSize) -> NSImage {
        if abs(image.size.width - size.width) < 0.5,
           abs(image.size.height - size.height) < 0.5 {
            return image
        }
        return NSImage(size: size, flipped: false) { bounds in
            image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
            return true
        }
    }

    private func cropFromFreeze(_ rect: CGRect) -> NSImage? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let frame = freezeFrames.first { NSMouseInRect(center, $0.screen.frame, false) }
            ?? freezeFrames.first
        guard let frame else { return nil }
        return ScreenCapturer.crop(frame.cgImage, rectInScreenPoints: rect, on: frame.screen)
    }

    private func showOverlays() {
        tearDownOverlays()
        // Window list + freeze frames before our panels cover the displays.
        windowHitTester = WindowHitTester.snapshot()
        freezeFrames = []
        for screen in NSScreen.screens {
            let cgImage = ScreenCapturer.captureDisplay(screen)
            if let cgImage {
                freezeFrames.append(FreezeFrame(screen: screen, cgImage: cgImage))
            }
            let backdrop = cgImage.map { NSImage(cgImage: $0, size: screen.frame.size) }
            let panel = SelectionPanel(screen: screen, freezeImage: backdrop)
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
        freezeFrames = []
        dragKind = nil
        currentRect = .null
        hoveredWindowRect = nil
        pendingWindowPick = nil
        annotateTool = .none
        let prefs = AnnotationPrefs.load()
        annotationStyle = prefs.style
        annotationKind = prefs.kind
        annotationHistory.reset()
        draftAnnotation = nil
        stopPencilSampling()
        historyCursor = nil
        playbackBaseImage = nil
        phase = .idle
        NSCursor.arrow.set()
    }

    private func installMonitors() {
        removeMonitors()

        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
        if let mon = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            guard let self else { return event }
            // Pass through so the floating toolbar can receive clicks.
            if let toolbar = self.toolbar, toolbar.containsGlobalPoint(NSEvent.mouseLocation) {
                NSCursor.arrow.set()
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
                NSCursor.arrow.set()
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
            // `,` / `.` snip-history browse (any phase while overlay is up).
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                if event.keyCode == 43 || event.charactersIgnoringModifiers == "," {
                    self.browseHistory(older: true)
                    return nil
                }
                if event.keyCode == 47 || event.charactersIgnoringModifiers == "." {
                    self.browseHistory(older: false)
                    return nil
                }
            }
            if self.phase == .refining {
                // ⌘Z undo; ⇧⌘Z / ⌘Y redo.
                if event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers?.lowercased() {
                    if chars == "z" {
                        if event.modifierFlags.contains(.shift) {
                            self.performRedo()
                        } else {
                            self.performUndo()
                        }
                        return nil
                    }
                    if chars == "y" {
                        self.performRedo()
                        return nil
                    }
                }
                // Delete / Forward Delete removes the selected annotation.
                if (event.keyCode == 51 || event.keyCode == 117),
                   self.selectedAnnotationID != nil {
                    self.deleteSelectedAnnotation()
                    return nil
                }
                // Return / keypad Enter confirms primary action while refining.
                if event.keyCode == 36 || event.keyCode == 76 {
                    self.confirm(self.primaryAction)
                    return nil
                }
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
        if phase == .idle, pendingWindowPick == nil {
            updateHoverHighlight(at: point)
            return
        }
        if phase == .refining, dragKind == nil {
            updateOverlayCursor(at: point)
        }
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
        updateOverlayCursor(at: NSEvent.mouseLocation)
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
            handleRefineMouseDown(at: point)
        }
    }

    private func handleRefineMouseDown(at point: CGPoint) {
        // Annotate tool: handle → resize; stroke/border → move; interior → draw (nested OK).
        if annotateTool != .none {
            switch annotationPointerTarget(at: point) {
            case .handle(let id, let handle):
                guard let ann = annotations.first(where: { $0.id == id }) else { return }
                annotationHistory.select(id)
                syncToolbar(from: ann)
                annotationHistory.beginGesture()
                dragKind = .annotateResize(id: id, handle: handle, start: ann, startPoint: point)
                resizeCursor(for: handle).set()

            case .border(let id):
                guard let ann = annotations.first(where: { $0.id == id }) else { return }
                annotationHistory.select(id)
                syncToolbar(from: ann)
                annotationHistory.beginGesture()
                dragKind = .annotateMove(id: id, start: ann, startPoint: point)
                NSCursor.closedHand.set()
                updateHighlight(showHandles: true)

            case .draw:
                annotationHistory.select(nil)
                let local = toLocal(point)
                dragKind = .annotateDraw(startLocal: local)
                draftAnnotation = makeDraftAnnotation(startingAt: local)
                // Pencil: hide reticle so only the ink tip shows (Snipaste).
                if annotateTool == .pencil {
                    AnnotationCursors.hidden.set()
                    startPencilSampling()
                } else {
                    AnnotationCursors.whitePlus.set()
                }
                updateHighlight(showHandles: true)

            case .outside:
                // Keep selection + annotations; ignore clicks in the dimmed area while annotating.
                break
            }
            return
        }

        // Selection refine (no annotate tool): interior moves; border resize; outside expands to point.
        annotationHistory.select(nil)
        if let handle = refineResizeHandle(at: point) {
            if currentRect.contains(point) {
                dragKind = .resize(handle: handle, startRect: currentRect, startPoint: point)
            } else {
                // Snipaste: click outside → that edge jumps to the pointer, then follows while dragged.
                dragKind = .expand(handle: handle, baseRect: currentRect)
                currentRect = expandedRect(handle: handle, baseRect: currentRect, to: point)
                updateHighlight(showHandles: true)
                repositionToolbar()
            }
            resizeCursor(for: handle).set()
        } else if currentRect.contains(point) {
            dragKind = .move(startRect: currentRect, startPoint: point)
            NSCursor.closedHand.set()
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

        case .expand(let handle, let baseRect):
            currentRect = expandedRect(handle: handle, baseRect: baseRect, to: point)
            updateHighlight(showHandles: true)
            repositionToolbar()

        case .annotateDraw(let startLocal):
            appendPencilOrShapeDraft(startLocal: startLocal, globalPoint: point)

        case .annotateMove(let id, let start, let startPoint):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            var next = start
            next.translate(by: CGSize(width: dx, height: dy))
            clampAnnotationInSelection(&next)
            updateAnnotation(id: id) { $0.payload = next.payload }
            updateHighlight(showHandles: true)

        case .annotateResize(let id, let handle, let start, let startPoint):
            let startGlobal = toGlobal(start.boundingRect)
            let resizedGlobal = resizedRect(
                handle: handle,
                startRect: startGlobal,
                startPoint: startPoint,
                point: point,
                minSize: minAnnotation
            )
            var local = clampAnnotationRect(toLocal(resizedGlobal))
            var next = start
            next.mapBoundingRect(to: local)
            updateAnnotation(id: id) { $0.payload = next.payload }
            updateHighlight(showHandles: true)
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
            updateOverlayCursor(at: point)

        case .refining:
            switch dragKind {
            case .annotateDraw:
                stopPencilSampling()
                if let draft = draftAnnotation {
                    draftAnnotation = nil
                    if isDraftWorthKeeping(draft) {
                        let ann = finalizedDraft(draft)
                        annotationHistory.commit { doc in
                            doc.marks.append(ann)
                            // Pencil: keep drawing clean — no auto-select / resize chrome.
                            doc.selectedID = ann.isPencil ? nil : ann.id
                        }
                        refreshHistoryChrome()
                    }
                }
            case .annotateMove, .annotateResize:
                annotationHistory.endGesture()
                refreshHistoryChrome()
            default:
                break
            }
            updateHighlight(showHandles: true)
            repositionToolbar()
            updateOverlayCursor(at: point)
        }
    }

    // MARK: - Annotation helpers

    private func toLocal(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - currentRect.minX, y: global.y - currentRect.minY)
    }

    private func toLocal(_ global: CGRect) -> CGRect {
        CGRect(
            x: global.origin.x - currentRect.minX,
            y: global.origin.y - currentRect.minY,
            width: global.width,
            height: global.height
        )
    }

    private func toGlobal(_ local: CGRect) -> CGRect {
        local.offsetBy(dx: currentRect.minX, dy: currentRect.minY)
    }

    private func clampLocal(_ p: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(p.x, 0), currentRect.width),
            y: min(max(p.y, 0), currentRect.height)
        )
    }

    private func clampAnnotationRect(_ rect: CGRect) -> CGRect {
        var r = rect
        r.size.width = max(r.width, minAnnotation)
        r.size.height = max(r.height, minAnnotation)
        r.origin.x = min(max(r.origin.x, 0), max(0, currentRect.width - r.width))
        r.origin.y = min(max(r.origin.y, 0), max(0, currentRect.height - r.height))
        if r.maxX > currentRect.width { r.size.width = currentRect.width - r.origin.x }
        if r.maxY > currentRect.height { r.size.height = currentRect.height - r.origin.y }
        return r
    }

    /// Keep mark geometry inside the selection without changing its size when possible.
    private func clampAnnotationInSelection(_ annotation: inout Annotation) {
        let bounds = annotation.boundingRect
        guard !bounds.isNull else { return }
        let maxX = max(0, currentRect.width - bounds.width)
        let maxY = max(0, currentRect.height - bounds.height)
        let ox = min(max(bounds.origin.x, 0), maxX)
        let oy = min(max(bounds.origin.y, 0), maxY)
        annotation.translate(by: CGSize(width: ox - bounds.origin.x, height: oy - bounds.origin.y))
    }

    /// Axis-aligned square / circle bounding box from drag start toward `toward`.
    private func constrainedSquare(from start: CGPoint, toward end: CGPoint) -> CGRect {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        let ox = dx < 0 ? -side : 0
        let oy = dy < 0 ? -side : 0
        return CGRect(x: start.x + ox, y: start.y + oy, width: side, height: side)
    }

    private func syncToolbar(from annotation: Annotation) {
        annotationStyle = annotation.style
        if annotation.isShape {
            annotationKind = annotation.kind
        }
        toolbar?.syncStyle(annotation.style, kind: annotationKind)
    }

    private func makeDraftAnnotation(startingAt local: CGPoint) -> Annotation {
        switch annotateTool {
        case .pencil:
            var style = annotationStyle
            style.isFilled = false
            return Annotation(points: [local], style: style)
        case .rectangle, .none:
            return Annotation(
                kind: annotationKind,
                rect: CGRect(origin: local, size: .zero),
                style: annotationStyle
            )
        }
    }

    private func appendPencilOrShapeDraft(startLocal: CGPoint, globalPoint: CGPoint) {
        let end = clampLocal(toLocal(globalPoint))
        let start = clampLocal(startLocal)
        draftAnnotation = updatedDraft(from: start, to: end)
        updateHighlight(showHandles: true)
    }

    /// Poll mouse while pencil is down so the stroke tracks between sparse drag events.
    private func startPencilSampling() {
        stopPencilSampling()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.samplePencilAtMouse()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pencilSampleTimer = timer
    }

    private func stopPencilSampling() {
        pencilSampleTimer?.invalidate()
        pencilSampleTimer = nil
    }

    private func samplePencilAtMouse() {
        guard case .annotateDraw(let startLocal) = dragKind, annotateTool == .pencil else {
            stopPencilSampling()
            return
        }
        // Shift-straight is endpoint-only; polling would fight it.
        if NSEvent.modifierFlags.contains(.shift) { return }
        appendPencilOrShapeDraft(startLocal: startLocal, globalPoint: NSEvent.mouseLocation)
    }

    private func updatedDraft(from start: CGPoint, to end: CGPoint) -> Annotation {
        switch annotateTool {
        case .pencil:
            var style = annotationStyle
            style.isFilled = false
            if NSEvent.modifierFlags.contains(.shift) {
                // Straight line at any angle (start → tip); no 45° quantization.
                return Annotation(points: [start, end], style: style)
            }
            // Append densely — never rubber-band a long segment from the last committed point.
            var points = draftAnnotation?.points ?? [start]
            if points.isEmpty { points = [start] }
            if let last = points.last {
                let distance = hypot(end.x - last.x, end.y - last.y)
                if distance >= pencilSampleSpacing {
                    points.append(end)
                }
            } else {
                points.append(end)
            }
            return Annotation(points: points, style: style)

        case .rectangle, .none:
            var draft = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )
            // Shift → square / circle from the drag start corner.
            if NSEvent.modifierFlags.contains(.shift) {
                draft = constrainedSquare(from: start, toward: end)
            }
            return Annotation(kind: annotationKind, rect: draft, style: annotationStyle)
        }
    }

    private func isDraftWorthKeeping(_ draft: Annotation) -> Bool {
        switch draft.payload {
        case .shape(_, let rect, _):
            return rect.width >= minAnnotation && rect.height >= minAnnotation
        case .pencil(let points, _):
            guard points.count >= 2, let first = points.first, let last = points.last else { return false }
            return hypot(last.x - first.x, last.y - first.y) >= minAnnotation
                || pathLength(points) >= minAnnotation
        }
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var total: CGFloat = 0
        for i in 0..<(points.count - 1) {
            total += hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        }
        return total
    }

    private func finalizedDraft(_ draft: Annotation) -> Annotation {
        switch draft.payload {
        case .shape(let kind, let rect, let style):
            return Annotation(kind: kind, rect: clampAnnotationRect(rect), style: style)
        case .pencil(let points, let style):
            let clamped = points.map(clampLocal)
            return Annotation(points: clamped, style: style)
        }
    }

    private func updateAnnotation(id: UUID, mutate: (inout Annotation) -> Void) {
        annotationHistory.mutateLive { doc in
            guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
            mutate(&doc.marks[idx])
        }
    }

    private func deleteSelectedAnnotation() {
        guard let id = selectedAnnotationID else { return }
        annotationHistory.commit { doc in
            doc.marks.removeAll { $0.id == id }
            doc.selectedID = nil
        }
        updateHighlight(showHandles: true)
        refreshHistoryChrome()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    /// Priority: selected handles → any stroke/border (topmost) → draw zone inside selection.
    private func annotationPointerTarget(at point: CGPoint) -> AnnotationPointerTarget {
        guard annotateTool != .none else { return .outside }
        guard currentRect.contains(point) else { return .outside }

        if let id = selectedAnnotationID,
           let ann = annotations.first(where: { $0.id == id }),
           let handle = hitTestAnnotationHandle(at: point, annotation: ann) {
            return .handle(id: id, handle: handle)
        }

        for ann in annotations.reversed() {
            if isOnAnnotationStroke(ann, at: point) {
                return .border(id: ann.id)
            }
        }

        return .draw
    }

    private func isOnAnnotationStroke(_ annotation: Annotation, at globalPoint: CGPoint) -> Bool {
        switch annotation.payload {
        case .shape(let kind, let localRect, let style):
            let rect = toGlobal(localRect)
            let halfStroke = style.isFilled ? 0 : style.strokeWidth / 2
            let tolerance = max(halfStroke + 2, annotationBorderHitSlop)
            let local = CGPoint(x: globalPoint.x - rect.minX, y: globalPoint.y - rect.minY)

            switch kind {
            case .rectangle:
                let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
                guard outer.contains(globalPoint) else { return false }
                if rect.width <= tolerance * 2 || rect.height <= tolerance * 2 {
                    return true
                }
                let inner = rect.insetBy(dx: tolerance, dy: tolerance)
                return !inner.contains(globalPoint)

            case .ellipse:
                return isOnEllipseRing(size: rect.size, localPoint: local, tolerance: tolerance)
            }

        case .pencil(let points, let style):
            let local = toLocal(globalPoint)
            let tolerance = max(style.strokeWidth / 2 + 2, annotationBorderHitSlop)
            return AnnotationDrawing.distance(from: local, toPolyline: points) <= tolerance
        }
    }

    private func hitTestAnnotationHandle(at point: CGPoint, annotation: Annotation) -> Handle? {
        // Pencil is freehand — no resize chrome (keeps the canvas uncluttered).
        guard !annotation.isPencil else { return nil }
        let global = toGlobal(annotation.boundingRect)
        for handle in Handle.allCases {
            if handleHitRect(handle, in: global).contains(point) {
                return handle
            }
        }
        return nil
    }

    /// `localPoint` is relative to the ellipse bounding rect's origin.
    private func isOnEllipseRing(size: CGSize, localPoint: CGPoint, tolerance: CGFloat) -> Bool {
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else { return false }

        let cx = w / 2
        let cy = h / 2
        let dx = localPoint.x - cx
        let dy = localPoint.y - cy

        // Avoid degenerate rings on tiny marks.
        let rxOuter = max(w / 2 + tolerance, 1)
        let ryOuter = max(h / 2 + tolerance, 1)
        let rxInner = max(w / 2 - tolerance, 0.5)
        let ryInner = max(h / 2 - tolerance, 0.5)

        let outer = (dx * dx) / (rxOuter * rxOuter) + (dy * dy) / (ryOuter * ryOuter)
        let inner = (dx * dx) / (rxInner * rxInner) + (dy * dy) / (ryInner * ryInner)
        return outer <= 1 && inner >= 1
    }

    private func updateOverlayCursor(at point: CGPoint) {
        guard phase == .refining else {
            NSCursor.arrow.set()
            return
        }
        if annotateTool != .none {
            updateAnnotateCursor(at: point)
        } else {
            updateRefineCursor(at: point)
        }
    }

    /// Selection-only refine: open hand to move; resize arrows on border / outside octants.
    private func updateRefineCursor(at point: CGPoint) {
        if let toolbar, toolbar.containsGlobalPoint(point) {
            NSCursor.arrow.set()
            return
        }
        if let handle = refineResizeHandle(at: point) {
            resizeCursor(for: handle).set()
        } else if currentRect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func updateAnnotateCursor(at point: CGPoint) {
        guard phase == .refining, annotateTool != .none else {
            NSCursor.arrow.set()
            return
        }
        if let toolbar, toolbar.containsGlobalPoint(point) {
            NSCursor.arrow.set()
            return
        }

        switch annotationPointerTarget(at: point) {
        case .handle(_, let handle):
            resizeCursor(for: handle).set()
        case .border:
            NSCursor.openHand.set()
        case .draw:
            if annotateTool == .pencil {
                AnnotationCursors.pencilCrosshair(color: annotationStyle.strokeColor).set()
            } else {
                AnnotationCursors.whitePlus.set()
            }
        case .outside:
            NSCursor.arrow.set()
        }
    }

    private func resizeCursor(for handle: Handle) -> NSCursor {
        let position: NSCursor.FrameResizePosition
        switch handle {
        case .top: position = .top
        case .bottom: position = .bottom
        case .left: position = .left
        case .right: position = .right
        case .topLeft: position = .topLeft
        case .topRight: position = .topRight
        case .bottomLeft: position = .bottomLeft
        case .bottomRight: position = .bottomRight
        }
        return NSCursor.frameResize(position: position, directions: .all)
    }

    private func setAnnotateTool(_ tool: AnnotateTool) {
        annotateTool = tool
        if tool == .none {
            annotationHistory.select(nil)
        } else if tool == .pencil, annotationStyle.isFilled {
            // Pencil has no fill; fall back to last stroke width.
            annotationStyle.isFilled = false
            AnnotationPrefs.save(style: annotationStyle, kind: annotationKind)
        }
        toolbar?.setAnnotateTool(tool)
        updateHighlight(showHandles: true)
        repositionToolbar()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    private func applyStyle(_ style: AnnotationStyle) {
        var next = style
        if annotateTool == .pencil {
            next.isFilled = false
        }
        annotationStyle = next
        AnnotationPrefs.save(style: next, kind: annotationKind)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }) {
            var applied = next
            // Don't push fill onto a pencil mark.
            if selected.isPencil {
                applied.isFilled = false
            }
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].style = applied
            }
            updateHighlight(showHandles: true)
            refreshHistoryChrome()
        }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    private func applyKind(_ kind: ShapeKind) {
        annotationKind = kind
        AnnotationPrefs.save(style: annotationStyle, kind: kind)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           selected.isShape {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].kind = kind
            }
            updateHighlight(showHandles: true)
            refreshHistoryChrome()
        }
    }

    private func performUndo() {
        guard annotationHistory.canUndo else { return }
        annotationHistory.undo()
        syncAfterHistoryChange()
    }

    private func performRedo() {
        guard annotationHistory.canRedo else { return }
        annotationHistory.redo()
        syncAfterHistoryChange()
    }

    private func syncAfterHistoryChange() {
        if let id = selectedAnnotationID,
           let ann = annotations.first(where: { $0.id == id }) {
            syncToolbar(from: ann)
        }
        updateHighlight(showHandles: true)
        refreshHistoryChrome()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    private func refreshHistoryChrome() {
        toolbar?.setHistoryAvailability(
            canUndo: annotationHistory.canUndo,
            canRedo: annotationHistory.canRedo
        )
    }

    // MARK: - Geometry

    /// Snipaste-style zones: deep interior → `nil` (move); border strip and outside
    /// octants (N/S/E/W + corners) → the resize handle for that direction.
    private func refineResizeHandle(at point: CGPoint) -> Handle? {
        guard !currentRect.isNull, currentRect.width > 0, currentRect.height > 0 else { return nil }
        let r = currentRect
        let t = selectionEdgeHit

        let inner = r.insetBy(dx: t, dy: t)
        if inner.width > 0, inner.height > 0, inner.contains(point) {
            return nil
        }

        let onLeft = point.x < r.minX + t
        let onRight = point.x > r.maxX - t
        let onBottom = point.y < r.minY + t
        let onTop = point.y > r.maxY - t

        if onTop && onLeft { return .topLeft }
        if onTop && onRight { return .topRight }
        if onBottom && onLeft { return .bottomLeft }
        if onBottom && onRight { return .bottomRight }
        if onTop { return .top }
        if onBottom { return .bottom }
        if onLeft { return .left }
        if onRight { return .right }
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
        point: CGPoint,
        minSize: CGFloat? = nil
    ) -> CGRect {
        let floor = minSize ?? minSelection
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
        if rect.width < floor { rect.size.width = floor }
        if rect.height < floor { rect.size.height = floor }
        return rect
    }

    /// Absolute edge placement for outside-click expand (opposite edges stay on `baseRect`).
    private func expandedRect(handle: Handle, baseRect: CGRect, to point: CGPoint, minSize: CGFloat? = nil) -> CGRect {
        let floor = minSize ?? minSelection
        var minX = baseRect.minX
        var maxX = baseRect.maxX
        var minY = baseRect.minY
        var maxY = baseRect.maxY

        switch handle {
        case .topLeft:
            minX = point.x
            maxY = point.y
        case .top:
            maxY = point.y
        case .topRight:
            maxX = point.x
            maxY = point.y
        case .left:
            minX = point.x
        case .right:
            maxX = point.x
        case .bottomLeft:
            minX = point.x
            minY = point.y
        case .bottom:
            minY = point.y
        case .bottomRight:
            maxX = point.x
            minY = point.y
        }

        if minX > maxX { swap(&minX, &maxX) }
        if minY > maxY { swap(&minY, &maxY) }

        var rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        if rect.width < floor { rect.size.width = floor }
        if rect.height < floor { rect.size.height = floor }
        return rect
    }

    private func clampRectToScreens() {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(currentRect)
        }) ?? NSScreen.main else { return }

        var r = currentRect
        // If the restored rect is larger than the screen, shrink to fit while keeping aspect.
        if r.width > screen.frame.width {
            r.size.width = screen.frame.width
        }
        if r.height > screen.frame.height {
            r.size.height = screen.frame.height
        }
        r.origin.x = min(max(r.origin.x, screen.frame.minX), screen.frame.maxX - r.width)
        r.origin.y = min(max(r.origin.y, screen.frame.minY), screen.frame.maxY - r.height)
        currentRect = r
    }

    // MARK: - History playback (, / .)

    private func browseHistory(older: Bool) {
        guard let store = historyStore, store.count > 0 else { return }

        let nextIndex: Int
        if let cursor = historyCursor {
            nextIndex = older ? cursor - 1 : cursor + 1
        } else if older {
            // First `,` jumps to newest record.
            nextIndex = store.count - 1
        } else {
            // First `.` with no cursor: already past newest — no-op.
            return
        }

        guard store.records.indices.contains(nextIndex),
              let record = store.record(at: nextIndex)
        else { return }

        historyCursor = nextIndex
        restoreRecord(record)
    }

    private func restoreRecord(_ record: SnipRecord) {
        dragKind = nil
        pendingWindowPick = nil
        hoveredWindowRect = nil
        draftAnnotation = nil
        annotateTool = .none
        let prefs = AnnotationPrefs.load()
        annotationStyle = prefs.style
        annotationKind = prefs.kind
        NSCursor.arrow.set()

        currentRect = record.selection
        clampRectToScreens()
        playbackBaseImage = record.baseImage
        annotationHistory.reset(to: record.document)

        phase = .refining
        updateHighlight(showHandles: true)
        showToolbar()
        refreshHistoryChrome()
    }

    // MARK: - Drawing / toolbar

    private func updateHighlight(showHandles: Bool) {
        let selected = selectedAnnotationID.flatMap { id in annotations.first(where: { $0.id == id }) }
        for panel in panels {
            panel.setSelection(
                currentRect,
                showHandles: showHandles && annotateTool == .none,
                handleVisualSize: handleVisualSize,
                annotations: annotations,
                draftAnnotation: draftAnnotation,
                selectedAnnotation: selected,
                annotationHandleSize: annotationHandleVisualSize,
                playbackImage: playbackBaseImage
            )
        }
    }

    private func showToolbar() {
        toolbar?.close()
        let bar = RefineToolbarController(
            primaryAction: primaryAction,
            initialTool: annotateTool,
            initialStyle: annotationStyle,
            initialKind: annotationKind
        ) { [weak self] event in
            guard let self else { return }
            switch event {
            case .confirm(let action):
                switch action {
                case .pin: self.confirm(.pin)
                case .copy: self.confirm(.copy)
                case .save: self.confirm(.save)
                case .cancel:
                    self.tearDownOverlays()
                    self.finish(.cancelled)
                }
            case .selectTool(let tool):
                self.setAnnotateTool(tool)
            case .styleChanged(let style):
                self.applyStyle(style)
            case .kindChanged(let kind):
                self.applyKind(kind)
            case .undo:
                self.performUndo()
            case .redo:
                self.performRedo()
            }
        }
        toolbar = bar
        refreshHistoryChrome()
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
    enum ConfirmAction {
        case pin
        case copy
        case save
        case cancel
    }

    enum Event {
        case confirm(ConfirmAction)
        case selectTool(AnnotateTool)
        case styleChanged(AnnotationStyle)
        case kindChanged(ShapeKind)
        case undo
        case redo
    }

    private let panel: NSPanel
    private let onEvent: (Event) -> Void
    private var style: AnnotationStyle
    private var tool: AnnotateTool
    private var kind: ShapeKind

    private let rootStack = NSStackView()
    private var shapeButton: NSButton!
    private var pencilButton: NSButton!
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private var subToolbarContainer: NSView!
    /// Shape-only chrome (fill + rect/oval). Hidden for pencil.
    private var shapeOnlyViews: [NSView] = []
    private var strokeButtons: [NSButton] = []
    private var fillButton: NSButton!
    private var rectKindButton: NSButton!
    private var ovalKindButton: NSButton!
    private var lineStyleButton: NSButton!
    private var colorPreview: NSView!

    init(
        primaryAction: SelectionOverlayController.ConfirmAction,
        initialTool: AnnotateTool,
        initialStyle: AnnotationStyle,
        initialKind: ShapeKind,
        onEvent: @escaping (Event) -> Void
    ) {
        self.onEvent = onEvent
        self.style = initialStyle
        self.tool = initialTool
        self.kind = initialKind
        self.panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()

        let content = RefineToolbarView(frame: .zero)
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.clear.cgColor

        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        // Snipaste: two separate chrome cards with a small gap (~4pt).
        rootStack.spacing = 4
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let mainCard = makeChromeCard()
        let mainRow = buildMainRow(primaryAction: primaryAction)
        embed(mainRow, in: mainCard)

        let optionsCard = makeChromeCard()
        let subRow = buildSubToolbar()
        embed(subRow, in: optionsCard)
        subToolbarContainer = optionsCard
        subToolbarContainer.isHidden = (initialTool == .none)

        rootStack.addArrangedSubview(mainCard)
        rootStack.addArrangedSubview(subToolbarContainer)

        content.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: content.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        refreshSelectionChrome()
        layoutPanel(content: content)

        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = content
    }

    private func buildMainRow(primaryAction: SelectionOverlayController.ConfirmAction) -> NSView {
        shapeButton = iconButton(
            systemName: "rectangle",
            tooltip: "Rectangle",
            enabled: true,
            action: #selector(shapeTapped)
        )
        pencilButton = iconButton(
            systemName: "pencil",
            tooltip: "Pen",
            enabled: true,
            action: #selector(pencilTapped)
        )

        let annotateViews: [NSView] = [
            shapeButton,
            iconButton(systemName: "arrow.up.right", tooltip: "Arrow", enabled: false, action: nil),
            pencilButton,
            iconButton(systemName: "paintbrush.pointed", tooltip: "Marker", enabled: false, action: nil),
            iconButton(systemName: "square.grid.3x3", tooltip: "Mosaic", enabled: false, action: nil),
            iconButton(systemName: "textformat", tooltip: "Text", enabled: false, action: nil),
            iconButton(systemName: "1.circle", tooltip: "Step", enabled: false, action: nil),
            iconButton(systemName: "magnifyingglass", tooltip: "Magnifier", enabled: false, action: nil),
            iconButton(systemName: "eraser", tooltip: "Eraser", enabled: false, action: nil),
        ]
        undoButton = iconButton(
            systemName: "arrow.uturn.backward",
            tooltip: "Undo",
            enabled: false,
            action: #selector(undoTapped)
        )
        redoButton = iconButton(
            systemName: "arrow.uturn.forward",
            tooltip: "Redo",
            enabled: false,
            action: #selector(redoTapped)
        )
        let editViews: [NSView] = [
            iconButton(systemName: "doc.text.viewfinder", tooltip: "OCR", enabled: false, action: nil),
            undoButton,
            redoButton,
        ]

        let cancel = iconButton(systemName: "xmark", tooltip: "Cancel", enabled: true, action: #selector(cancelTapped))
        let pin = iconButton(systemName: "pin.fill", tooltip: "Pin", enabled: true, action: #selector(pinTapped))
        let save = iconButton(systemName: "square.and.arrow.down", tooltip: "Save", enabled: true, action: #selector(saveTapped))
        let copy = iconButton(systemName: "doc.on.doc", tooltip: "Copy", enabled: true, action: #selector(copyTapped))
        let more = iconButton(systemName: "ellipsis", tooltip: "More", enabled: false, action: nil)

        let primary: NSButton
        switch primaryAction {
        case .pin, .save:
            primary = pin
        case .copy:
            primary = copy
        }
        primary.keyEquivalent = "\r"
        panel.defaultButtonCell = primary.cell as? NSButtonCell

        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)

        for v in annotateViews { stack.addArrangedSubview(v) }
        stack.addArrangedSubview(divider())
        for v in editViews { stack.addArrangedSubview(v) }
        stack.addArrangedSubview(divider())
        for v in [cancel, pin, save, copy, more] { stack.addArrangedSubview(v) }
        return stack
    }

    private func buildSubToolbar() -> NSView {
        let stack = NSStackView(views: [])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)

        // Switch group 1: three stroke widths + fill (mutually exclusive).
        strokeButtons = StrokeWidthOption.allCases.map { option in
            let button = NSButton(frame: .zero)
            button.bezelStyle = .inline
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.imagePosition = .imageOnly
            button.toolTip = "Stroke"
            button.target = self
            button.action = #selector(strokeTapped(_:))
            button.tag = option.rawValue
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 22),
                button.heightAnchor.constraint(equalToConstant: 22),
            ])
            button.image = strokeDotImage(diameter: option.previewDiameter, selected: false)
            return button
        }
        for b in strokeButtons { stack.addArrangedSubview(b) }

        fillButton = NSButton(frame: .zero)
        fillButton.bezelStyle = .inline
        fillButton.isBordered = false
        fillButton.setButtonType(.momentaryChange)
        fillButton.imagePosition = .imageOnly
        fillButton.toolTip = "Fill"
        fillButton.target = self
        fillButton.action = #selector(fillTapped)
        fillButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fillButton.widthAnchor.constraint(equalToConstant: 22),
            fillButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        fillButton.image = fillSwatchImage(selected: false)
        stack.addArrangedSubview(fillButton)

        let afterFillDivider = miniDivider()
        stack.addArrangedSubview(afterFillDivider)

        // Switch group 2: rectangle ↔ ellipse / circle.
        rectKindButton = iconButton(
            systemName: "rectangle",
            tooltip: "Rectangle",
            enabled: true,
            action: #selector(rectKindTapped)
        )
        ovalKindButton = iconButton(
            systemName: "oval",
            tooltip: "Ellipse / Circle",
            enabled: true,
            action: #selector(ovalKindTapped)
        )
        stack.addArrangedSubview(rectKindButton)
        stack.addArrangedSubview(ovalKindButton)

        let afterKindDivider = miniDivider()
        stack.addArrangedSubview(afterKindDivider)

        // Shared by shape + pencil: hide fill / kind for pencil (Snipaste pen options).
        // Keep `afterKindDivider` visible so stroke → line-style stays separated.
        shapeOnlyViews = [fillButton, afterFillDivider, rectKindButton, ovalKindButton]

        // Item 7: border line style dropdown (Snipaste 5 patterns).
        lineStyleButton = NSButton(frame: .zero)
        lineStyleButton.bezelStyle = .inline
        lineStyleButton.isBordered = false
        lineStyleButton.setButtonType(.momentaryChange)
        lineStyleButton.imagePosition = .imageOnly
        lineStyleButton.toolTip = "Border style"
        lineStyleButton.target = self
        lineStyleButton.action = #selector(lineStyleTapped(_:))
        lineStyleButton.translatesAutoresizingMaskIntoConstraints = false
        lineStyleButton.wantsLayer = true
        lineStyleButton.layer?.cornerRadius = 10
        lineStyleButton.layer?.backgroundColor = NSColor(calibratedWhite: 0.96, alpha: 1).cgColor
        lineStyleButton.layer?.borderWidth = 1
        lineStyleButton.layer?.borderColor = NSColor(calibratedWhite: 0.78, alpha: 1).cgColor
        NSLayoutConstraint.activate([
            lineStyleButton.widthAnchor.constraint(equalToConstant: 56),
            lineStyleButton.heightAnchor.constraint(equalToConstant: 22),
        ])
        stack.addArrangedSubview(lineStyleButton)

        stack.addArrangedSubview(miniDivider())

        // Color preview (24pt) + 2×10 grid: chips 11pt, gap 2pt (measured from Snipaste @2x).
        let preview = NSView(frame: .zero)
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 3
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor(calibratedWhite: 0.35, alpha: 1).cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            preview.widthAnchor.constraint(equalToConstant: 24),
            preview.heightAnchor.constraint(equalToConstant: 24),
        ])
        colorPreview = preview
        stack.addArrangedSubview(preview)

        let swatchGrid = NSStackView(views: [])
        swatchGrid.orientation = .vertical
        swatchGrid.spacing = 2
        swatchGrid.alignment = .leading
        swatchGrid.wantsLayer = true
        swatchGrid.layer?.masksToBounds = false

        let allSwatches = PaletteColor.allCases
        let columns = 10
        for rowStart in stride(from: 0, to: allSwatches.count, by: columns) {
            let row = NSStackView(views: [])
            row.orientation = .horizontal
            row.spacing = 2
            row.wantsLayer = true
            row.layer?.masksToBounds = false
            let end = min(rowStart + columns, allSwatches.count)
            for swatch in allSwatches[rowStart..<end] {
                let control = PaletteSwatchControl(swatch: swatch) { [weak self] picked in
                    guard let self else { return }
                    self.style.strokeColor = picked.color
                    self.refreshSelectionChrome()
                    self.onEvent(.styleChanged(self.style))
                }
                row.addArrangedSubview(control)
            }
            swatchGrid.addArrangedSubview(row)
        }
        stack.addArrangedSubview(swatchGrid)

        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func makeChromeCard() -> NSView {
        let card = NSView(frame: .zero)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = 6
        card.layer?.masksToBounds = false
        card.layer?.shadowColor = NSColor.black.cgColor
        card.layer?.shadowOpacity = 0.18
        card.layer?.shadowRadius = 6
        card.layer?.shadowOffset = CGSize(width: 0, height: -1)
        card.translatesAutoresizingMaskIntoConstraints = false
        return card
    }

    private func embed(_ child: NSView, in card: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            child.topAnchor.constraint(equalTo: card.topAnchor),
            child.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
    }

    private func layoutPanel(content: NSView) {
        content.layoutSubtreeIfNeeded()
        let fitting = rootStack.fittingSize
        let size = CGSize(width: max(fitting.width, 280), height: max(fitting.height, 28))
        content.frame = CGRect(origin: .zero, size: size)
        panel.setContentSize(size)
    }

    private func refreshSelectionChrome() {
        tintSelected(shapeButton, selected: tool == .rectangle)
        tintSelected(pencilButton, selected: tool == .pencil)
        colorPreview.layer?.backgroundColor = style.strokeColor.cgColor

        let shapeExtrasVisible = (tool == .rectangle)
        for view in shapeOnlyViews {
            view.isHidden = !shapeExtrasVisible
        }

        let selectedStroke = StrokeWidthOption.matching(style.strokeWidth)
        let treatAsStroke = !style.isFilled || tool == .pencil
        for button in strokeButtons {
            let option = StrokeWidthOption(rawValue: button.tag) ?? .medium
            let on = treatAsStroke && option == selectedStroke
            button.image = strokeDotImage(diameter: option.previewDiameter, selected: on)
            tintSelected(button, selected: on)
        }
        fillButton.image = fillSwatchImage(selected: style.isFilled && tool == .rectangle)
        tintSelected(fillButton, selected: style.isFilled && tool == .rectangle)

        tintSelected(rectKindButton, selected: kind == .rectangle)
        tintSelected(ovalKindButton, selected: kind == .ellipse)

        lineStyleButton.image = lineStylePreviewImage(style.lineStyle)
        let lineEnabled = treatAsStroke
        lineStyleButton.isEnabled = lineEnabled
        lineStyleButton.alphaValue = lineEnabled ? 1 : 0.45
    }

    private func tintSelected(_ button: NSButton, selected: Bool) {
        button.contentTintColor = selected
            ? NSColor.systemBlue
            : NSColor(calibratedWhite: 0.22, alpha: 1)
        if selected {
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.12).cgColor
            button.layer?.cornerRadius = 4
        } else {
            button.layer?.backgroundColor = nil
        }
    }

    private func strokeDotImage(diameter: CGFloat, selected: Bool) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let color = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.25, alpha: 1)
            color.setFill()
            let r = CGRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            NSBezierPath(ovalIn: r).fill()
            return true
        }
    }

    private func fillSwatchImage(selected: Bool) -> NSImage {
        let size = CGSize(width: 18, height: 18)
        return NSImage(size: size, flipped: false) { rect in
            let color = selected ? NSColor.systemBlue : NSColor(calibratedWhite: 0.25, alpha: 1)
            color.setFill()
            let r = CGRect(x: 3, y: 3, width: 12, height: 12)
            NSBezierPath(roundedRect: r, xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
    }

    /// Compact pill preview: line pattern + chevron (Snipaste-like).
    private func lineStylePreviewImage(_ lineStyle: StrokeLineStyle) -> NSImage {
        let size = CGSize(width: 52, height: 18)
        let previewStroke: CGFloat = 2
        return NSImage(size: size, flipped: false) { rect in
            let ink = NSColor(calibratedWhite: 0.28, alpha: 1)
            ink.setStroke()

            let y = rect.midY
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 6, y: y))
            line.line(to: NSPoint(x: 34, y: y))
            line.lineWidth = previewStroke
            line.lineCapStyle = .butt
            let dash = lineStyle.dashPattern(strokeWidth: previewStroke)
            if !dash.isEmpty {
                line.setLineDash(dash, count: dash.count, phase: 0)
            }
            line.stroke()

            // Up / down chevrons on the trailing edge.
            let chevronX: CGFloat = 42
            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: chevronX, y: y + 4.5))
            chevron.line(to: NSPoint(x: chevronX + 3.5, y: y + 1.5))
            chevron.line(to: NSPoint(x: chevronX + 7, y: y + 4.5))
            chevron.move(to: NSPoint(x: chevronX, y: y - 4.5))
            chevron.line(to: NSPoint(x: chevronX + 3.5, y: y - 1.5))
            chevron.line(to: NSPoint(x: chevronX + 7, y: y - 4.5))
            chevron.lineWidth = 1.2
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            ink.setStroke()
            chevron.stroke()
            return true
        }
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

    private func miniDivider() -> NSView {
        let wrap = NSView(frame: .zero)
        wrap.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            wrap.widthAnchor.constraint(equalToConstant: 6),
            wrap.heightAnchor.constraint(equalToConstant: 20),
        ])
        let line = NSView(frame: .zero)
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor(calibratedWhite: 0.82, alpha: 1).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(line)
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 12),
            line.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
        ])
        return wrap
    }

    @objc private func shapeTapped() {
        selectTool(tool == .rectangle ? .none : .rectangle)
    }

    @objc private func pencilTapped() {
        selectTool(tool == .pencil ? .none : .pencil)
    }

    private func selectTool(_ next: AnnotateTool) {
        tool = next
        if next == .pencil {
            style.isFilled = false
        }
        subToolbarContainer.isHidden = (next == .none)
        refreshSelectionChrome()
        if let content = panel.contentView {
            layoutPanel(content: content)
        }
        onEvent(.selectTool(next))
    }

    @objc private func strokeTapped(_ sender: NSButton) {
        let option = StrokeWidthOption(rawValue: sender.tag) ?? .medium
        style.strokeWidth = option.points
        style.isFilled = false
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

    @objc private func fillTapped() {
        guard tool == .rectangle else { return }
        style.isFilled = true
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

    @objc private func rectKindTapped() {
        kind = .rectangle
        refreshSelectionChrome()
        onEvent(.kindChanged(kind))
    }

    @objc private func ovalKindTapped() {
        kind = .ellipse
        refreshSelectionChrome()
        onEvent(.kindChanged(kind))
    }

    @objc private func lineStyleTapped(_ sender: NSButton) {
        guard !style.isFilled else { return }
        let menu = NSMenu()
        for option in StrokeLineStyle.allCases {
            let item = NSMenuItem(
                title: "",
                action: #selector(lineStyleMenuPicked(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = option.rawValue
            item.state = (option == style.lineStyle) ? .on : .off
            item.toolTip = option.toolTip
            item.image = lineStyleMenuImage(option)
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func lineStyleMenuPicked(_ sender: NSMenuItem) {
        guard let option = StrokeLineStyle(rawValue: sender.tag) else { return }
        style.lineStyle = option
        style.isFilled = false
        refreshSelectionChrome()
        onEvent(.styleChanged(style))
    }

    private func lineStyleMenuImage(_ lineStyle: StrokeLineStyle) -> NSImage {
        let size = CGSize(width: 56, height: 14)
        let previewStroke: CGFloat = 2
        return NSImage(size: size, flipped: false) { rect in
            NSColor(calibratedWhite: 0.25, alpha: 1).setStroke()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 2, y: rect.midY))
            line.line(to: NSPoint(x: rect.width - 2, y: rect.midY))
            line.lineWidth = previewStroke
            line.lineCapStyle = .butt
            let dash = lineStyle.dashPattern(strokeWidth: previewStroke)
            if !dash.isEmpty {
                line.setLineDash(dash, count: dash.count, phase: 0)
            }
            line.stroke()
            return true
        }
    }

    @objc private func pinTapped() { onEvent(.confirm(.pin)) }
    @objc private func copyTapped() { onEvent(.confirm(.copy)) }
    @objc private func saveTapped() { onEvent(.confirm(.save)) }
    @objc private func cancelTapped() { onEvent(.confirm(.cancel)) }
    @objc private func undoTapped() { onEvent(.undo) }
    @objc private func redoTapped() { onEvent(.redo) }

    func setAnnotateTool(_ tool: AnnotateTool) {
        self.tool = tool
        if tool == .pencil {
            style.isFilled = false
        }
        subToolbarContainer.isHidden = (tool == .none)
        refreshSelectionChrome()
        if let content = panel.contentView {
            layoutPanel(content: content)
        }
    }

    func syncStyle(_ style: AnnotationStyle, kind: ShapeKind) {
        self.style = style
        self.kind = kind
        refreshSelectionChrome()
    }

    func setHistoryAvailability(canUndo: Bool, canRedo: Bool) {
        setHistoryButton(undoButton, enabled: canUndo)
        setHistoryButton(redoButton, enabled: canRedo)
    }

    private func setHistoryButton(_ button: NSButton, enabled: Bool) {
        button.isEnabled = enabled
        button.contentTintColor = enabled
            ? NSColor(calibratedWhite: 0.22, alpha: 1)
            : NSColor(calibratedWhite: 0.55, alpha: 1)
    }

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

    init(screen: NSScreen, freezeImage: NSImage?) {
        self.screenFrame = screen.frame
        self.overlayView = SelectionOverlayNSView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            freezeImage: freezeImage
        )

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        // Opaque when frozen so live desktop cannot show through.
        isOpaque = freezeImage != nil
        backgroundColor = freezeImage != nil ? .black : .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = overlayView
    }

    func setSelection(
        _ globalRect: CGRect,
        showHandles: Bool,
        handleVisualSize: CGFloat,
        annotations: [Annotation],
        draftAnnotation: Annotation?,
        selectedAnnotation: Annotation?,
        annotationHandleSize: CGFloat,
        playbackImage: NSImage?
    ) {
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
        overlayView.annotations = annotations
        overlayView.draftAnnotation = draftAnnotation
        overlayView.selectedAnnotation = selectedAnnotation
        overlayView.annotationHandleSize = annotationHandleSize
        overlayView.playbackImage = playbackImage
        overlayView.needsDisplay = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionOverlayNSView: NSView {
    var selectionRect: CGRect = .null
    var showHandles = false
    var handleVisualSize: CGFloat = 8
    var annotations: [Annotation] = []
    var draftAnnotation: Annotation?
    var selectedAnnotation: Annotation?
    var annotationHandleSize: CGFloat = 7
    /// Historical crop drawn inside the selection (`,` / `.` playback).
    var playbackImage: NSImage?

    private let freezeImage: NSImage?
    private let accent = NSColor.systemBlue

    init(frame frameRect: NSRect, freezeImage: NSImage?) {
        self.freezeImage = freezeImage
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { freezeImage != nil }

    override func draw(_ dirtyRect: NSRect) {
        // Freeze backdrop (Snipaste-style). Without it, fall back to punch-through dim.
        if let freezeImage {
            freezeImage.draw(
                in: bounds,
                from: CGRect(origin: .zero, size: freezeImage.size),
                operation: .copy,
                fraction: 1
            )
        }

        let dimPath = NSBezierPath(rect: bounds)
        if !selectionRect.isNull, selectionRect.width > 0, selectionRect.height > 0 {
            dimPath.append(NSBezierPath(rect: selectionRect))
            dimPath.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.45).setFill()
        dimPath.fill()

        guard !selectionRect.isNull, selectionRect.width > 0, selectionRect.height > 0 else { return }

        // Legacy path when freeze capture failed: clear the hole to the live desktop.
        if freezeImage == nil {
            NSGraphicsContext.current?.compositingOperation = .clear
            selectionRect.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }

        // History playback: paint archived base inside the selection (rest of screen stays freeze).
        if let playbackImage {
            playbackImage.draw(
                in: selectionRect,
                from: CGRect(origin: .zero, size: playbackImage.size),
                operation: .copy,
                fraction: 1
            )
        }

        let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        accent.setStroke()
        border.stroke()

        drawAnnotations()

        if showHandles {
            drawSelectionHandles()
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

    private func drawAnnotations() {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selectionRect).addClip()

        let origin = selectionRect.origin
        for ann in annotations {
            AnnotationDrawing.draw(ann, origin: origin)
        }

        if let draft = draftAnnotation {
            AnnotationDrawing.draw(draft, origin: origin)
        }

        if let selected = selectedAnnotation, !selected.isPencil {
            let r = selected.boundingRect.offsetBy(dx: origin.x, dy: origin.y)
            AnnotationDrawing.drawHandles(in: r, size: annotationHandleSize, accent: accent)
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawSelectionHandles() {
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

// MARK: - Palette swatch (Snipaste-like hover grow)

/// Fixed layout cell; chip starts small and scales up on hover.
/// Fill is drawn flush to the 1pt border (no CALayer inset gap).
private final class PaletteSwatchControl: NSView {
    /// Snipaste @2x: 22 device-px → 11pt chip; 4px gap → 2pt (via stack spacing).
    static let cellSize: CGFloat = 11
    private static let restSize: CGFloat = 11
    private static let hoverSize: CGFloat = 13.5

    private let swatch: PaletteColor
    private let onPick: (PaletteColor) -> Void
    private let chip = PaletteSwatchChip()
    private var trackingArea: NSTrackingArea?

    init(swatch: PaletteColor, onPick: @escaping (PaletteColor) -> Void) {
        self.swatch = swatch
        self.onPick = onPick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.cellSize),
            heightAnchor.constraint(equalToConstant: Self.cellSize),
        ])

        chip.swatchColor = swatch.color
        addSubview(chip)
        layoutChip(size: Self.restSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        animateChip(size: Self.hoverSize)
    }

    override func mouseExited(with event: NSEvent) {
        animateChip(size: Self.restSize)
    }

    override func mouseDown(with event: NSEvent) {
        onPick(swatch)
    }

    private func animateChip(size: CGFloat) {
        let origin = (Self.cellSize - size) / 2
        let target = CGRect(x: origin, y: origin, width: size, height: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.09
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            chip.animator().frame = target
        }
        chip.needsDisplay = true
    }

    private func layoutChip(size: CGFloat) {
        let origin = (Self.cellSize - size) / 2
        chip.frame = CGRect(x: origin, y: origin, width: size, height: size)
        chip.needsDisplay = true
    }
}

private final class PaletteSwatchChip: NSView {
    var swatchColor: NSColor = .black

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = max(1.75, bounds.width * 0.22)
        let fillPath = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        swatchColor.setFill()
        fillPath.fill()

        // Stroke on the same rect edge — no gap between fill and border.
        let strokePath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: max(radius - 0.5, 0.5),
            yRadius: max(radius - 0.5, 0.5)
        )
        strokePath.lineWidth = 1
        NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
        strokePath.stroke()
    }
}
