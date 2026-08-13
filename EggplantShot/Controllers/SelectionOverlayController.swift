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
    private var textStyle: TextStyle = TextAnnotationPrefs.load()
    private let annotationHistory = AnnotationHistory()
    /// In-progress mark while dragging (selection-local geometry).
    private var draftAnnotation: Annotation?
    /// Text click-to-place / click-to-edit (resolved on mouse-up if drag is tiny).
    private var textClickCandidate: (id: UUID?, start: CGPoint, wasSelected: Bool)?
    /// Snipaste hover outline while the pointer is over a text mark.
    private var hoveredTextID: UUID?
    /// Active inline text editor (selection-local mark id).
    private var editingTextID: UUID?
    private var textEditorHost: SelectionPanel?
    /// Bordered transparent chrome hosting the field editor (CALayer borders on clear scrolls are unreliable).
    private var textChromeView: TextEditChromeView?
    private var textEditor: AnnotationTextView?
    private var textEditBaselineString: String = ""
    private var textEditBaselineRect: CGRect = .null
    private let textClickDragThreshold: CGFloat = 4

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
        /// Interior of a text mark (text tool): click to edit, not move.
        case interior(id: UUID)
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

        // Window list + freeze frames before our panels cover the displays.
        windowHitTester = WindowHitTester.snapshot()
        let captured = await ScreenCapturer.captureAllDisplays()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.phase = .idle
            showOverlays(freezeCaptures: captured)
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
        endTextEditing(commit: true)
        guard !currentRect.isNull,
              currentRect.width >= minSelection,
              currentRect.height >= minSelection
        else {
            tearDownOverlays()
            finish(.cancelled)
            return
        }
        // Crop stays the blue selection (Snipaste): marks outside are kept in the document
        // for `,` / `.` edit, but clipped out of the baked pin/copy/save image.
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

    private func showOverlays(freezeCaptures: [(screen: NSScreen, image: CGImage)]) {
        tearDownOverlays()
        freezeFrames = freezeCaptures.map { FreezeFrame(screen: $0.screen, cgImage: $0.image) }
        let imageByScreenID = Dictionary(
            uniqueKeysWithValues: freezeCaptures.map { ($0.screen.displayID, $0.image) }
        )
        for screen in NSScreen.screens {
            let cgImage = imageByScreenID[screen.displayID]
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
        textStyle = TextAnnotationPrefs.load()
        annotationHistory.reset()
        draftAnnotation = nil
        textClickCandidate = nil
        hoveredTextID = nil
        discardTextEditor()
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
            // Pass through while interacting with the inline text editor.
            if self.isPointInTextEditor(NSEvent.mouseLocation) {
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
            if self.isPointInTextEditor(NSEvent.mouseLocation) {
                return
            }
            self.handleMouse(event)
        }) {
            eventMonitors.append(mon)
        }

        if let mon = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                if self.editingTextID != nil {
                    self.endTextEditing(commit: true)
                    return nil
                }
                self.tearDownOverlays()
                self.finish(.cancelled)
                return nil
            }
            // While editing text: keep typing in the field editor; route ⌘Z to its
            // *private* undo manager (never the shared app one — that crashes after
            // the editor is torn down with stale `_undoRedoTextOperation:` targets).
            if self.editingTextID != nil {
                if event.modifierFlags.contains(.command),
                   let chars = event.charactersIgnoringModifiers?.lowercased() {
                    if chars == "z" {
                        if event.modifierFlags.contains(.shift) {
                            self.textEditor?.undoManager?.redo()
                        } else {
                            self.textEditor?.undoManager?.undo()
                        }
                        return nil
                    }
                    if chars == "y" {
                        self.textEditor?.undoManager?.redo()
                        return nil
                    }
                }
                return event
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
            updateHoveredText(at: point)
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
        // Finish any open text editor before starting a new gesture (unless clicking it).
        if editingTextID != nil {
            if let chrome = textChromeView,
               let host = textEditorHost,
               chrome.frame.contains(CGPoint(
                x: point.x - host.screenFrame.minX,
                y: point.y - host.screenFrame.minY
               )) {
                return
            }
            endTextEditing(commit: true)
        }

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

            case .interior(let id):
                guard let ann = annotations.first(where: { $0.id == id }) else { return }
                annotationHistory.select(id)
                syncToolbar(from: ann)
                // Interior click edits immediately (Snipaste: body is for typing, not moving).
                if annotateTool == .text, ann.isText {
                    startTextEditing(id: id)
                }
                updateHighlight(showHandles: true)

            case .draw:
                if annotateTool == .text {
                    // Click-to-place resolved on mouse-up (ignore tiny drag).
                    textClickCandidate = (nil, point, false)
                    updateHighlight(showHandles: true)
                    return
                }
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
            // Annotate marks may live outside the selection — don't clamp into the blue rect.
            var next = start
            next.mapBoundingRect(to: toLocal(resizedGlobal))
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

            // Text: click-to-place / click-to-re-edit when drag stayed tiny.
            if let candidate = textClickCandidate {
                textClickCandidate = nil
                let moved = hypot(point.x - candidate.start.x, point.y - candidate.start.y)
                if moved < textClickDragThreshold {
                    if let id = candidate.id {
                        if candidate.wasSelected {
                            startTextEditing(id: id)
                        }
                    } else if annotateTool == .text {
                        placeAndEditText(at: candidate.start)
                    }
                }
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

    /// Marks may live outside the blue selection (fullscreen annotate). No clamp.
    private func clampAnnotationInSelection(_ annotation: inout Annotation) {
        _ = annotation
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
        if annotation.isText {
            textStyle = annotation.textStyle
            toolbar?.syncTextStyle(textStyle)
            return
        }
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
        case .text:
            let rect = Annotation.fittedTextRect(
                string: "",
                style: textStyle,
                origin: local,
                anchor: .leadingMidY
            )
            return Annotation(string: "", rect: rect, style: textStyle)
        case .rectangle, .none:
            return Annotation(
                kind: annotationKind,
                rect: CGRect(origin: local, size: .zero),
                style: annotationStyle
            )
        }
    }

    private func appendPencilOrShapeDraft(startLocal: CGPoint, globalPoint: CGPoint) {
        // Selection-local, may extend outside the blue rect.
        let end = toLocal(globalPoint)
        draftAnnotation = updatedDraft(from: startLocal, to: end)
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

        case .text:
            // Text is click-to-place; drag-draw is unused.
            return makeDraftAnnotation(startingAt: start)

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
        case .text:
            return true
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
            return Annotation(kind: kind, rect: rect, style: style)
        case .pencil(let points, let style):
            return Annotation(points: points, style: style)
        case .text(let string, let rect, let style):
            return Annotation(string: string, rect: rect, style: style)
        }
    }

    private func updateAnnotation(id: UUID, mutate: (inout Annotation) -> Void) {
        annotationHistory.mutateLive { doc in
            guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
            mutate(&doc.marks[idx])
        }
    }

    private func deleteSelectedAnnotation() {
        endTextEditing(commit: false)
        guard let id = selectedAnnotationID else { return }
        annotationHistory.commit { doc in
            doc.marks.removeAll { $0.id == id }
            doc.selectedID = nil
        }
        updateHighlight(showHandles: true)
        refreshHistoryChrome()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    /// Priority: selected handles → text interior/border → any stroke/border (topmost) → draw.
    /// Annotate tools work fullscreen (Snipaste), not only inside the blue selection.
    private func annotationPointerTarget(at point: CGPoint) -> AnnotationPointerTarget {
        guard annotateTool != .none else { return .outside }

        if let id = selectedAnnotationID,
           id != editingTextID,
           let ann = annotations.first(where: { $0.id == id }),
           !ann.isText,
           let handle = hitTestAnnotationHandle(at: point, annotation: ann) {
            return .handle(id: id, handle: handle)
        }

        for ann in annotations.reversed() {
            if ann.id == editingTextID { continue }
            if ann.isText {
                let global = toGlobal(ann.boundingRect)
                switch textFrameHit(at: point, globalRect: global) {
                case .none:
                    break
                case .border:
                    return .border(id: ann.id)
                case .interior:
                    // Text tool: interior is edit. Other tools: whole body still moves.
                    if annotateTool == .text {
                        return .interior(id: ann.id)
                    }
                    return .border(id: ann.id)
                }
                continue
            }
            if isOnAnnotationStroke(ann, at: point) {
                return .border(id: ann.id)
            }
        }

        // Any point on the overlay is a draw target while a tool is active.
        return .draw
    }

    private enum TextFrameHit {
        case border
        case interior
    }

    /// Border strip is the move handle; interior is for typing.
    /// Hits stay *inside* the frame (edge inclusive) so adjacent text marks can sit flush.
    private func textFrameHit(at point: CGPoint, globalRect: CGRect) -> TextFrameHit? {
        guard globalRect.contains(point) else { return nil }
        let inset = min(3, min(globalRect.width, globalRect.height) / 4)
        if globalRect.width <= inset * 2 || globalRect.height <= inset * 2 {
            return .border
        }
        let inner = globalRect.insetBy(dx: inset, dy: inset)
        return inner.contains(point) ? .interior : .border
    }

    private func textMarkID(at point: CGPoint) -> UUID? {
        for ann in annotations.reversed() {
            if ann.id == editingTextID { continue }
            guard ann.isText else { continue }
            if toGlobal(ann.boundingRect).contains(point) {
                return ann.id
            }
        }
        return nil
    }

    private func updateHoveredText(at point: CGPoint) {
        let id = textMarkID(at: point)
        guard id != hoveredTextID else { return }
        hoveredTextID = id
        updateHighlight(showHandles: true)
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

        case .text:
            return false
        }
    }

    private func hitTestAnnotationHandle(at point: CGPoint, annotation: Annotation) -> Handle? {
        // Pencil / text: no resize chrome.
        guard !annotation.isPencil, !annotation.isText else { return nil }
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
        case .interior:
            NSCursor.iBeam.set()
        case .draw:
            if annotateTool == .pencil {
                AnnotationCursors.pencilCrosshair(color: annotationStyle.strokeColor).set()
            } else if annotateTool == .text {
                NSCursor.iBeam.set()
            } else {
                AnnotationCursors.whitePlus.set()
            }
        case .outside:
            // Should be rare while a tool is active (draw covers the overlay).
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
        if tool != annotateTool {
            endTextEditing(commit: true)
        }
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
           let selected = annotations.first(where: { $0.id == id }),
           !selected.isText {
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

    private func applyTextStyle(_ style: TextStyle) {
        textStyle = style
        TextAnnotationPrefs.save(style)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           selected.isText {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].textStyle = style
            }
            if editingTextID == id {
                applyTextStyleToEditor(style)
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
        endTextEditing(commit: false)
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

    // MARK: - Text editing

    private func placeAndEditText(at globalPoint: CGPoint) {
        // Selection-local, may be outside the blue rect (Snipaste free placement).
        let local = toLocal(globalPoint)
        let rect = Annotation.fittedTextRect(
            string: "",
            style: textStyle,
            origin: local,
            anchor: .leadingMidY
        )
        let ann = Annotation(string: "", rect: rect, style: textStyle)
        annotationHistory.commit { doc in
            doc.marks.append(ann)
            doc.selectedID = ann.id
        }
        refreshHistoryChrome()
        updateHighlight(showHandles: true)
        startTextEditing(id: ann.id)
    }

    private func startTextEditing(id: UUID) {
        guard let ann = annotations.first(where: { $0.id == id }), ann.isText else { return }
        if editingTextID == id { return }
        endTextEditing(commit: true)

        let globalRect = toGlobal(ann.boundingRect)
        guard let panel = panels.first(where: { $0.screenFrame.contains(CGPoint(x: globalRect.midX, y: globalRect.midY)) })
                ?? panels.first(where: { $0.screenFrame.intersects(globalRect) })
                ?? panels.first
        else { return }

        editingTextID = id
        textEditBaselineString = ann.string
        textEditBaselineRect = ann.boundingRect
        textEditorHost = panel

        let size = Annotation.fittingTextSize(string: ann.string, style: ann.textStyle)
        let localInPanel = CGRect(
            x: globalRect.origin.x - panel.screenFrame.origin.x,
            y: globalRect.maxY - size.height - panel.screenFrame.origin.y,
            width: size.width,
            height: size.height
        )

        // Draw border in `draw(_:)` — layer borders on clear views often don't show.
        // Text view fills chrome; hairline border sits in the padding zone (no extra inset).
        let chrome = TextEditChromeView(frame: localInPanel)
        let tv = AnnotationTextView(frame: chrome.bounds)
        tv.autoresizingMask = [.width, .height]
        tv.string = ann.string
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = ann.textStyle.makeFont()
        tv.textColor = ann.textStyle.color
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        // Only the explicit “background” style toggle fills behind glyphs.
        if ann.textStyle.hasBackground {
            tv.drawsBackground = true
            tv.backgroundColor = Self.textEditorBackground(for: ann.textStyle.color)
        }
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.containerSize = CGSize(width: 10_000, height: 10_000)
        tv.textContainerInset = NSSize(
            width: ann.textStyle.textPadding,
            height: ann.textStyle.textPadding
        )
        tv.delegate = TextEditingBridge.shared
        TextEditingBridge.shared.owner = self
        tv.onNeedsFit = { [weak self] in
            self?.resizeTextEditorToFit()
        }

        chrome.addSubview(tv)
        panel.contentView?.addSubview(chrome)
        panel.makeKeyAndOrderFront(nil)
        tv.window?.makeFirstResponder(tv)

        textChromeView = chrome
        textEditor = tv
        applyTextChromeContrast(
            style: ann.textStyle,
            globalPoint: CGPoint(x: globalRect.midX, y: globalRect.midY)
        )
        resizeTextEditorToFit()
        updateHighlight(showHandles: true)
    }

    private func endTextEditing(commit: Bool) {
        guard let id = editingTextID else { return }
        let string = textEditor?.string ?? textEditBaselineString
        let editorFrame = textChromeView?.frame
        let host = textEditorHost
        let style = annotations.first(where: { $0.id == id })?.textStyle ?? textStyle
        discardTextEditor()

        guard commit else {
            updateHighlight(showHandles: true)
            return
        }

        let trimmedEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if trimmedEmpty {
            annotationHistory.commit { doc in
                doc.marks.removeAll { $0.id == id }
                if doc.selectedID == id { doc.selectedID = nil }
            }
            refreshHistoryChrome()
            updateHighlight(showHandles: true)
            return
        }

        // Size to content (same as the live editor), anchored at the editor’s top-left.
        var newRect = textEditBaselineRect
        if let editorFrame, let host {
            let globalTopLeft = CGPoint(
                x: editorFrame.minX + host.screenFrame.minX,
                y: editorFrame.maxY + host.screenFrame.minY
            )
            let maxW = max(40, host.screenFrame.maxX - (editorFrame.minX + host.screenFrame.minX) - 4)
            let size = Annotation.fittingTextSize(string: string, style: style, maxWidth: maxW)
            newRect = CGRect(
                x: globalTopLeft.x - currentRect.minX,
                y: globalTopLeft.y - size.height - currentRect.minY,
                width: size.width,
                height: size.height
            )
        } else {
            newRect = Annotation.fittedTextRect(
                string: string,
                style: style,
                origin: CGPoint(x: textEditBaselineRect.minX, y: textEditBaselineRect.maxY)
            )
        }

        let baselineString = textEditBaselineString
        let baselineRect = textEditBaselineRect
        if string != baselineString || newRect != baselineRect {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].string = string
                doc.marks[idx].rect = newRect
                doc.selectedID = id
            }
            refreshHistoryChrome()
        } else {
            annotationHistory.select(id)
        }
        updateHighlight(showHandles: true)
    }

    private func discardTextEditor() {
        if let tv = textEditor {
            // Drop typing undo before releasing the view — shared/stale targets crash on ⌘Z.
            tv.clearIsolatedUndo()
            tv.window?.makeFirstResponder(nil)
        }
        textChromeView?.removeFromSuperview()
        textChromeView = nil
        textEditor?.onNeedsFit = nil
        textEditor = nil
        textEditorHost = nil
        editingTextID = nil
        TextEditingBridge.shared.owner = nil
    }

    private func applyTextStyleToEditor(_ style: TextStyle) {
        guard let tv = textEditor else { return }
        tv.font = style.makeFont()
        tv.textColor = style.color
        if style.hasBackground {
            tv.drawsBackground = true
            tv.backgroundColor = Self.textEditorBackground(for: style.color)
            tv.textContainerInset = NSSize(width: style.textPadding, height: style.textPadding)
        } else {
            tv.drawsBackground = false
            tv.backgroundColor = .clear
            tv.textContainerInset = NSSize(width: style.textPadding, height: style.textPadding)
        }
        let sample: CGPoint
        if let chrome = textChromeView, let host = textEditorHost {
            sample = CGPoint(
                x: chrome.frame.midX + host.screenFrame.minX,
                y: chrome.frame.midY + host.screenFrame.minY
            )
        } else {
            sample = NSEvent.mouseLocation
        }
        applyTextChromeContrast(style: style, globalPoint: sample)
        resizeTextEditorToFit()
    }

    func resizeTextEditorToFit() {
        guard let tv = textEditor, let chrome = textChromeView, let host = textEditorHost else { return }
        let style: TextStyle = {
            if let id = editingTextID,
               let ann = annotations.first(where: { $0.id == id }) {
                return ann.textStyle
            }
            return textStyle
        }()
        // Grow with glyphs (including IME marked / preedit); wrap only near the trailing screen edge.
        let maxW = max(40, host.screenFrame.width - chrome.frame.minX - 4)
        let minH = ceil(style.makeFont().boundingRectForFont.height) + style.textPadding * 2
        let size = tv.fittingSize(
            padding: style.textPadding,
            caretWidth: TextStyle.caretWidth,
            minHeight: minH,
            maxWidth: maxW
        )

        var frame = chrome.frame
        let top = frame.maxY
        frame.size.width = size.width
        frame.size.height = size.height
        frame.origin.y = top - size.height

        let screen = host.screenFrame
        frame.origin.x = min(max(frame.origin.x, 0), max(0, screen.width - frame.width))
        if frame.maxY > screen.height {
            frame.origin.y = screen.height - frame.height
        }
        if frame.minY < 0 {
            frame.origin.y = 0
        }

        chrome.frame = frame
        tv.frame = chrome.bounds
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.containerSize = CGSize(width: max(frame.width, maxW), height: 10_000)
        tv.textContainer?.widthTracksTextView = false
        chrome.needsDisplay = true
    }

    private static func textEditorBackground(for color: NSColor) -> NSColor {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55
            ? NSColor.black.withAlphaComponent(0.55)
            : NSColor.white.withAlphaComponent(0.85)
    }

    /// Hairline + caret: white on dark, black on light (not the palette / text color).
    private func applyTextChromeContrast(style: TextStyle, globalPoint: CGPoint) {
        let color = contrastChromeColor(style: style, at: globalPoint)
        textChromeView?.strokeColor = color
        textEditor?.insertionPointColor = color
    }

    private func contrastChromeColor(style: TextStyle, at globalPoint: CGPoint) -> NSColor {
        if style.hasBackground {
            let bg = Self.textEditorBackground(for: style.color)
            return Self.isLightColor(bg) ? .black : .white
        }
        return freezeContrastColor(at: globalPoint)
    }

    private func freezeContrastColor(at globalPoint: CGPoint) -> NSColor {
        let frame = freezeFrames.first { NSMouseInRect(globalPoint, $0.screen.frame, false) }
            ?? freezeFrames.first
        var luminance: CGFloat = 0.2
        if let frame,
           let sampled = ScreenCapturer.averageLuminance(
            in: frame.cgImage,
            aroundPointInScreenPoints: globalPoint,
            on: frame.screen
           ) {
            luminance = sampled
        }
        if !currentRect.isNull, !currentRect.contains(globalPoint) {
            // Overlay dim is 45% black over the freeze.
            luminance *= 0.55
        }
        return luminance < 0.55 ? .white : .black
    }

    private static func isLightColor(_ color: NSColor) -> Bool {
        let rgb = color.usingColorSpace(.genericRGB) ?? color
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.55
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
        endTextEditing(commit: false)
        dragKind = nil
        pendingWindowPick = nil
        hoveredWindowRect = nil
        draftAnnotation = nil
        textClickCandidate = nil
        hoveredTextID = nil
        annotateTool = .none
        let prefs = AnnotationPrefs.load()
        annotationStyle = prefs.style
        annotationKind = prefs.kind
        textStyle = TextAnnotationPrefs.load()
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

    private func isPointInTextEditor(_ point: CGPoint) -> Bool {
        guard let chrome = textChromeView, let host = textEditorHost else { return false }
        let local = CGPoint(
            x: point.x - host.screenFrame.minX,
            y: point.y - host.screenFrame.minY
        )
        return chrome.frame.contains(local)
    }

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
                playbackImage: playbackBaseImage,
                editingAnnotationID: editingTextID,
                hoveredTextID: hoveredTextID
            )
        }
    }

    private func showToolbar() {
        toolbar?.close()
        let bar = RefineToolbarController(
            primaryAction: primaryAction,
            initialTool: annotateTool,
            initialStyle: annotationStyle,
            initialKind: annotationKind,
            initialTextStyle: textStyle
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
            case .textStyleChanged(let style):
                self.applyTextStyle(style)
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
