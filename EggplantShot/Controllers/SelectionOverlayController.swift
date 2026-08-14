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
        /// OCR finished; `text` may be empty when nothing was recognized.
        case ocr(text: String)
    }

    enum Phase {
        case idle
        case drawing
        case refining
    }

    enum DragKind {
        case draw(start: CGPoint)
        case move(startRect: CGRect, startPoint: CGPoint)
        case resize(handle: Handle, startRect: CGRect, startPoint: CGPoint)
        /// Outside the selection: opposite edges stay fixed; active edge(s) track the pointer absolutely.
        case expand(handle: Handle, baseRect: CGRect)
        /// Shape / arrow / pencil in-progress stroke (tool decides payload).
        case annotateDraw(startLocal: CGPoint)
        case annotateMove(id: UUID, start: Annotation, startPoint: CGPoint, magnifierPart: MagnifierPart?)
        case annotateResize(
            id: UUID,
            handle: Handle,
            start: Annotation,
            startPoint: CGPoint,
            magnifierPart: MagnifierPart?
        )
        case annotateEndpoint(id: UUID, endpoint: ArrowEndpoint, start: Annotation)
    }

    enum Handle: CaseIterable {
        case topLeft, top, topRight
        case left, right
        case bottomLeft, bottom, bottomRight
    }

    var panels: [SelectionPanel] = []
    var toolbar: RefineToolbarController?
    var continuation: CheckedContinuation<Outcome, Never>?
    var phase: Phase = .idle
    var dragKind: DragKind?
    var currentRect: CGRect = .null
    var primaryAction: ConfirmAction = .pin
    /// When true (Capture and copy): lock / drag-complete copies immediately — no refine toolbar.
    var skipsRefine = false
    var eventMonitors: [Any] = []

    /// Shared snip history for `,` / `.` playback (owned by `SnipController`).
    var historyStore: SnipHistoryStore?
    /// Index into `historyStore.records` while browsing; `nil` = not browsing.
    var historyCursor: Int?
    /// When set, refine/confirm uses this unannotated base instead of cropping the live freeze.
    var playbackBaseImage: NSImage?

    /// Snapshot of app windows taken before overlays cover the screen.
    var windowHitTester = WindowHitTester.snapshot()
    /// Per-display freeze frames captured before overlays appear (Snipaste-style).
    var freezeFrames: [FreezeFrame] = []
    /// Window frame under the cursor while idle (Cocoa global coords).
    var hoveredWindowRect: CGRect?

    struct FreezeFrame {
        let screen: NSScreen
        let cgImage: CGImage
    }
    /// On mouse-down over a window: wait to see if this is a click-lock or a free drag.
    var pendingWindowPick: (start: CGPoint, frame: CGRect)?

    // MARK: Annotation state

    var annotateTool: AnnotateTool = .none
    var annotationStyle: AnnotationStyle = AnnotationPrefs.load().style
    /// Sub-toolbar rect / oval switch (next draw + selected mark).
    var annotationKind: ShapeKind = AnnotationPrefs.load().kind
    var arrowCaps: ArrowCaps = AnnotationPrefs.loadArrowCaps()
    var textStyle: TextStyle = TextAnnotationPrefs.load()
    var mosaicStyle: MosaicStyle = AnnotationPrefs.loadMosaicStyle()
    var mosaicDrawMode: MosaicDrawMode = AnnotationPrefs.loadMosaicDrawMode()
    var markerStyle: MarkerStyle = AnnotationPrefs.loadMarkerStyle()
    var markerDrawMode: MosaicDrawMode = AnnotationPrefs.loadMarkerDrawMode()
    var eraserStyle: EraserStyle = AnnotationPrefs.loadEraserStyle()
    var eraserDrawMode: MosaicDrawMode = AnnotationPrefs.loadEraserDrawMode()
    var stepStyle: StepStyle = StepAnnotationPrefs.load()
    var magnifierStyle: MagnifierStyle = MagnifierAnnotationPrefs.load().style
    var magnifierKind: ShapeKind = MagnifierAnnotationPrefs.load().kind
    let annotationHistory = AnnotationHistory()
    /// In-progress mark while dragging (selection-local geometry).
    var draftAnnotation: Annotation?
    /// Text / step click-to-place (resolved on mouse-up if drag is tiny).
    var textClickCandidate: (id: UUID?, start: CGPoint, wasSelected: Bool)?
    /// Snipaste hover outline while the pointer is over a text mark.
    var hoveredTextID: UUID?
    /// Snipaste hover: dashed outline over a non-selected marker region.
    var hoveredMarkerRegionID: UUID?
    /// Magnifier lenses under the cursor (reveal nested source when decluttering).
    var hoveredMagnifierLensIDs: Set<UUID> = []
    /// Active inline text editor (selection-local mark id).
    var editingTextID: UUID?
    var textEditorHost: SelectionPanel?
    /// Bordered transparent chrome hosting the field editor (CALayer borders on clear scrolls are unreliable).
    var textChromeView: TextEditChromeView?
    var textEditor: AnnotationTextView?
    var textEditBaselineString: String = ""
    var textEditBaselineRect: CGRect = .null
    /// Chrome frame at the start of a live-move while editing (panel-local).
    var textChromeDragStartFrame: CGRect?
    let textClickDragThreshold: CGFloat = 4
    /// Extra hit outside the text hairline so the border is easy to grab.
    let textBorderOutwardSlop: CGFloat = 2

    var annotations: [Annotation] { annotationHistory.document.marks }
    var selectedAnnotationID: UUID? { annotationHistory.document.selectedID }

    let handleVisualSize: CGFloat = 8
    let annotationHandleVisualSize: CGFloat = 7
    let handleHitSize: CGFloat = 12
    /// Border strip + outside octants use this thickness for Snipaste-style resize hit/cursor.
    let selectionEdgeHit: CGFloat = 8
    let minSelection: CGFloat = 2
    let minAnnotation: CGFloat = 4
    /// Freehand sample distance (points). Coarse enough to avoid point bloat; mouse-drag
    /// events alone drive the stroke (no high-Hz tip poll).
    let pencilSampleSpacing: CGFloat = 2
    /// Movement past this distance abandons window pick and starts free drag.
    let windowPickDragThreshold: CGFloat = 4
    /// Half-width of the annotation border hit corridor (beyond stroke).
    let annotationBorderHitSlop: CGFloat = 5

    /// Where the pointer sits relative to annotations while an annotate tool is active.
    enum AnnotationPointerTarget {
        case handle(id: UUID, handle: Handle)
        case arrowEndpoint(id: UUID, endpoint: ArrowEndpoint)
        case border(id: UUID)
        /// Interior of a text mark (text tool): click to edit, not move.
        case interior(id: UUID)
        case draw
        case outside
    }

    var isActive: Bool { continuation != nil }

    func beginSelection(
        primaryAction: ConfirmAction = .pin,
        skipsRefine: Bool = false,
        pinFrames: [CGRect] = []
    ) async -> Outcome {
        if continuation != nil {
            cancel()
        }
        self.primaryAction = primaryAction
        self.skipsRefine = skipsRefine
        historyCursor = nil
        playbackBaseImage = nil

        // Window list + freeze frames before our panels cover the displays.
        // Pin frames so hover / click-lock can target pinned images for re-snip.
        windowHitTester = WindowHitTester.snapshot(additionalFrames: pinFrames)
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

    func finish(_ outcome: Outcome) {
        guard let continuation else { return }
        self.continuation = nil
        phase = .idle
        continuation.resume(returning: outcome)
    }

    func confirm(_ action: ConfirmAction) {
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

    /// Crop selection → dismiss overlay → OCR → hand text to `SnipController` (clipboard + sound).
    func performOCR() {
        endTextEditing(commit: true)
        guard !currentRect.isNull,
              currentRect.width >= minSelection,
              currentRect.height >= minSelection
        else {
            tearDownOverlays()
            finish(.cancelled)
            return
        }
        let rect = currentRect
        let image: NSImage?
        if let playback = playbackBaseImage {
            image = Self.baseImageMatchingSelection(playback, size: rect.size)
        } else {
            image = cropFromFreeze(rect)
        }
        tearDownOverlays()
        guard let image else {
            finish(.cancelled)
            return
        }
        Task { @MainActor in
            let text = await TextRecognizer.recognize(image)
            finish(.ocr(text: text))
        }
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

    func cropFromFreeze(_ rect: CGRect) -> NSImage? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let frame = freezeFrames.first { NSMouseInRect(center, $0.screen.frame, false) }
            ?? freezeFrames.first
        guard let frame else { return nil }
        return ScreenCapturer.crop(frame.cgImage, rectInScreenPoints: rect, on: frame.screen)
    }

    func showOverlays(freezeCaptures: [(screen: NSScreen, image: CGImage)]) {
        tearDownOverlays()
        freezeFrames = freezeCaptures.map { FreezeFrame(screen: $0.screen, cgImage: $0.image) }
        let imageByScreenID = Dictionary(
            uniqueKeysWithValues: freezeCaptures.map { ($0.screen.displayID, $0.image) }
        )
        for screen in NSScreen.screens {
            let cgImage = imageByScreenID[screen.displayID]
            let backdrop = cgImage.map { NSImage(cgImage: $0, size: screen.frame.size) }
            let panel = SelectionPanel(screen: screen, freezeImage: backdrop)
            panel.onCursorUpdate = { [weak self] in
                self?.reassertOverlayCursor()
            }
            panel.cursorMode = .selectingPlus
            panels.append(panel)
            panel.orderFrontRegardless()
        }

        // Cursor rects only apply on the key window — activate first, then makeKey.
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        if let panel = panels.first(where: { NSMouseInRect(mouse, $0.screenFrame, false) }) ?? panels.first {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(panel.contentView)
            if let view = panel.contentView {
                panel.invalidateCursorRects(for: view)
            }
        }

        installMonitors()
        updateHoverHighlight(at: mouse)
    }

    func tearDownOverlays() {
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
        arrowCaps = AnnotationPrefs.loadArrowCaps()
        textStyle = TextAnnotationPrefs.load()
        mosaicStyle = AnnotationPrefs.loadMosaicStyle()
        mosaicDrawMode = AnnotationPrefs.loadMosaicDrawMode()
        markerStyle = AnnotationPrefs.loadMarkerStyle()
        markerDrawMode = AnnotationPrefs.loadMarkerDrawMode()
        eraserStyle = AnnotationPrefs.loadEraserStyle()
        eraserDrawMode = AnnotationPrefs.loadEraserDrawMode()
        stepStyle = StepAnnotationPrefs.load()
        let magPrefs = MagnifierAnnotationPrefs.load()
        magnifierStyle = magPrefs.style
        magnifierKind = magPrefs.kind
        annotationHistory.reset()
        draftAnnotation = nil
        textClickCandidate = nil
        hoveredTextID = nil
        hoveredMarkerRegionID = nil
        hoveredMagnifierLensIDs = []
        discardTextEditor()
        historyCursor = nil
        playbackBaseImage = nil
        phase = .idle
        // Don't NSCursor.arrow.set() — previous app restores its own cursor when it becomes key.
    }

    func installMonitors() {
        removeMonitors()

        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
        if let mon = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            guard let self else { return event }
            let point = NSEvent.mouseLocation
            // Pass through so the floating toolbar can receive clicks.
            if let toolbar = self.toolbar, toolbar.containsGlobalPoint(point) {
                NSCursor.arrow.set()
                return event
            }
            // Always drive the cursor ourselves (incl. over the text editor).
            if event.type == .mouseMoved, self.phase == .refining, self.dragKind == nil {
                self.updateHoveredText(at: point)
                self.updateHoveredMarkerRegion(at: point)
                self.updateHoveredMagnifier(at: point)
                self.updateOverlayCursor(at: point)
            }
            // Live-moving the editing chrome: swallow so NSTextView cannot steal the drag.
            if self.isDraggingEditingText {
                self.handleMouse(event)
                return nil
            }
            // Typing / text-selection inside the editing frame only.
            if self.shouldPassThroughToTextEditor(at: point, event: event) {
                return event
            }
            self.handleMouse(event)
            return nil
        }) {
            eventMonitors.append(mon)
        }

        if let mon = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            guard let self else { return }
            let point = NSEvent.mouseLocation
            if let toolbar = self.toolbar, toolbar.containsGlobalPoint(point) {
                NSCursor.arrow.set()
                return
            }
            if event.type == .mouseMoved, self.phase == .refining, self.dragKind == nil {
                self.updateHoveredText(at: point)
                self.updateHoveredMarkerRegion(at: point)
                self.updateHoveredMagnifier(at: point)
                self.updateOverlayCursor(at: point)
            }
            if self.isDraggingEditingText {
                self.handleMouse(event)
                return
            }
            if self.shouldPassThroughToTextEditor(at: point, event: event) {
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

        // ⌘ up/down: refresh move-vs-draw cursor over pencil / mosaic / eraser without waiting for mouse move.
        let flagsMask: NSEvent.EventTypeMask = .flagsChanged
        if let mon = NSEvent.addLocalMonitorForEvents(matching: flagsMask, handler: { [weak self] event in
            self?.handleAnnotateModifierFlagsChanged()
            return event
        }) {
            eventMonitors.append(mon)
        }
        if let mon = NSEvent.addGlobalMonitorForEvents(matching: flagsMask, handler: { [weak self] _ in
            self?.handleAnnotateModifierFlagsChanged()
        }) {
            eventMonitors.append(mon)
        }
    }

    /// ⌘ over pencil / mosaic / eraser marks: temporary move (cursor updates on key alone).
    func handleAnnotateModifierFlagsChanged() {
        guard phase == .refining, annotateTool != .none, dragKind == nil else { return }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func removeMonitors() {
        for m in eventMonitors {
            NSEvent.removeMonitor(m)
        }
        eventMonitors.removeAll()
    }

    func handleMouse(_ event: NSEvent) {
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

    func handleMouseMoved(at point: CGPoint) {
        if phase == .idle {
            if pendingWindowPick == nil {
                updateHoverHighlight(at: point)
            }
            // Selecting cursor comes from AppKit cursor rects on the key overlay.
            return
        }
        if phase == .drawing {
            return
        }
        if phase == .refining, dragKind == nil {
            updateHoveredText(at: point)
            updateHoveredMarkerRegion(at: point)
            updateOverlayCursor(at: point)
        }
    }

    func updateHoverHighlight(at point: CGPoint) {
        let frame = windowHitTester.windowFrame(at: point)
        hoveredWindowRect = frame
        if let frame {
            currentRect = frame
        } else {
            currentRect = .null
        }
        updateHighlight(showHandles: false)
    }

    func lockWindowSelection(_ frame: CGRect) {
        pendingWindowPick = nil
        hoveredWindowRect = nil
        currentRect = frame
        enterRefineOrAutoConfirm()
    }

    /// After window lock or free-drag mouse-up: refine + toolbar, or immediate confirm when `skipsRefine`.
    func enterRefineOrAutoConfirm() {
        if skipsRefine {
            confirm(primaryAction)
            return
        }
        phase = .refining
        setOverlayCursorMode(.controllerDriven)
        updateHighlight(showHandles: true)
        showToolbar()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func beginFreeDraw(from start: CGPoint) {
        pendingWindowPick = nil
        hoveredWindowRect = nil
        phase = .drawing
        dragKind = .draw(start: start)
        currentRect = CGRect(origin: start, size: .zero)
        updateHighlight(showHandles: false)
        setOverlayCursorMode(.selectingPlus)
    }

    func handleMouseDown(at point: CGPoint) {
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

    func handleRefineMouseDown(at point: CGPoint) {
        // Finish any open text editor before starting a new gesture — except live-move on its border.
        if let editingID = editingTextID {
            switch annotationPointerTarget(at: point) {
            case .border(let id) where id == editingID:
                break // fall through → annotateMove, stay editing
            case .interior(let id) where id == editingID:
                // Monitor should pass this through; ignore if it still arrives.
                return
            default:
                endTextEditing(commit: true)
            }
        }

        // Annotate tool: handle → resize; stroke/border → move; interior → draw (nested OK).
        if annotateTool != .none {
            switch annotationPointerTarget(at: point) {
            case .handle(let id, let handle):
                guard let ann = annotations.first(where: { $0.id == id }) else { return }
                annotationHistory.select(id)
                syncToolbar(from: ann)
                annotationHistory.beginGesture()
                let part: MagnifierPart? = ann.isMagnifier
                    ? (hitTestMagnifierHandle(at: point, annotation: ann)?.part ?? .lens)
                    : nil
                dragKind = .annotateResize(
                    id: id,
                    handle: handle,
                    start: ann,
                    startPoint: point,
                    magnifierPart: part
                )
                resizeCursor(for: handle).set()

            case .arrowEndpoint(let id, let endpoint):
                guard let ann = annotations.first(where: { $0.id == id }) else { return }
                annotationHistory.select(id)
                syncToolbar(from: ann)
                annotationHistory.beginGesture()
                dragKind = .annotateEndpoint(id: id, endpoint: endpoint, start: ann)
                AnnotationCursors.move.set()
                updateHighlight(showHandles: true)

            case .border(let id):
                guard var ann = annotations.first(where: { $0.id == id }) else { return }
                // While editing, use the live chrome geometry as the move baseline.
                if id == editingTextID, let live = editingTextGlobalRect() {
                    ann.mapBoundingRect(to: toLocal(live))
                    textChromeDragStartFrame = textChromeView?.frame
                } else {
                    textChromeDragStartFrame = nil
                }
                annotationHistory.select(id)
                syncToolbar(from: ann)
                annotationHistory.beginGesture()
                let part: MagnifierPart? = ann.isMagnifier
                    ? magnifierMovePart(at: point, annotation: ann)
                    : nil
                dragKind = .annotateMove(
                    id: id,
                    start: ann,
                    startPoint: point,
                    magnifierPart: part
                )
                AnnotationCursors.move.set()
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
                // Border strip / handles still resize the crop; outside is for annotate (no octant expand).
                if beginSelectionEdgeDragIfNeeded(at: point, allowOutsideExpand: false) { return }
                if annotateTool == .text || annotateTool == .step {
                    // Click-to-place resolved on mouse-up (ignore tiny drag).
                    textClickCandidate = (nil, point, false)
                    updateHighlight(showHandles: true)
                    return
                }
                annotationHistory.select(nil)
                let local = toLocal(point)
                dragKind = .annotateDraw(startLocal: local)
                draftAnnotation = makeDraftAnnotation(startingAt: local)
                // Pencil: hide reticle so only the ink shows.
                // Mosaic / marker / eraser: keep the translucent brush tip while stroking
                // (a fully hidden tip looks like a black blob on macOS).
                if annotateTool == .pencil {
                    AnnotationCursors.hidden.set()
                } else if annotateTool == .mosaic, mosaicDrawMode == .freehand {
                    AnnotationCursors.mosaicCrosshair(brushWidth: mosaicStyle.brushWidth).set()
                } else if annotateTool == .marker, markerDrawMode == .freehand {
                    AnnotationCursors.mosaicCrosshair(brushWidth: markerStyle.brushWidth).set()
                } else if annotateTool == .eraser, eraserDrawMode == .freehand {
                    AnnotationCursors.mosaicCrosshair(brushWidth: eraserStyle.brushWidth).set()
                } else {
                    AnnotationCursors.whitePlus.set()
                }
                updateHighlight(showHandles: true)

            case .outside:
                // Unreachable while a tool is armed (`annotationPointerTarget` returns `.draw`).
                break
            }
            return
        }

        // Selection refine (no annotate tool): interior moves; border resize; outside expands to point.
        annotationHistory.select(nil)
        if beginSelectionEdgeDragIfNeeded(at: point, allowOutsideExpand: true) {
            return
        }
        if currentRect.contains(point) {
            dragKind = .move(startRect: currentRect, startPoint: point)
            AnnotationCursors.move.set()
        }
    }

    /// Starts crop resize (border strip) or, when allowed, Snipaste-style expand (outside octant).
    /// Mark chrome must win first. While annotating, pass `allowOutsideExpand: false` so the
    /// dimmed area stays available for drawing.
    @discardableResult
    func beginSelectionEdgeDragIfNeeded(at point: CGPoint, allowOutsideExpand: Bool) -> Bool {
        guard let handle = refineResizeHandle(at: point, allowOutsideExpand: allowOutsideExpand) else {
            return false
        }
        annotationHistory.select(nil)
        if allowOutsideExpand, !currentRect.contains(point) {
            // Snipaste: click outside → that edge jumps to the pointer, then follows while dragged.
            dragKind = .expand(handle: handle, baseRect: currentRect)
            setSelectionRect(expandedRect(handle: handle, baseRect: currentRect, to: point))
            updateHighlight(showHandles: true)
            repositionToolbar()
        } else {
            dragKind = .resize(handle: handle, startRect: currentRect, startPoint: point)
        }
        resizeCursor(for: handle).set()
        return true
    }

    func handleMouseDragged(at point: CGPoint) {
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
            setSelectionRect(startRect.offsetBy(dx: dx, dy: dy))
            clampRectToScreens()
            updateHighlight(showHandles: true)
            repositionToolbar()

        case .resize(let handle, let startRect, let startPoint):
            setSelectionRect(resizedRect(handle: handle, startRect: startRect, startPoint: startPoint, point: point))
            updateHighlight(showHandles: true)
            repositionToolbar()

        case .expand(let handle, let baseRect):
            setSelectionRect(expandedRect(handle: handle, baseRect: baseRect, to: point))
            updateHighlight(showHandles: true)
            repositionToolbar()

        case .annotateDraw(let startLocal):
            appendPencilOrShapeDraft(startLocal: startLocal, globalPoint: point)

        case .annotateMove(let id, let start, let startPoint, let magnifierPart):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            var next = start
            if let magnifierPart, next.isMagnifier {
                next.translateMagnifierPart(magnifierPart, by: CGSize(width: dx, height: dy))
            } else {
                next.translate(by: CGSize(width: dx, height: dy))
            }
            clampAnnotationInSelection(&next)
            updateAnnotation(id: id) { $0.payload = next.payload }
            if id == editingTextID {
                repositionEditingChrome(dragDelta: CGSize(width: dx, height: dy))
                textEditBaselineRect = next.boundingRect
            }
            updateHighlight(showHandles: true)

        case .annotateResize(let id, let handle, let start, let startPoint, let magnifierPart):
            var next = start
            if magnifierPart != nil, start.isMagnifier {
                // Lens handles only: resize selection area; source syncs at fixed scale.
                let startGlobal = toGlobal(start.magnifierLens)
                let resizedGlobal = resizedRect(
                    handle: handle,
                    startRect: startGlobal,
                    startPoint: startPoint,
                    point: point,
                    minSize: minAnnotation
                )
                next.resizeMagnifierLens(to: toLocal(resizedGlobal))
            } else {
                let startGlobal = toGlobal(start.boundingRect)
                let resizedGlobal = resizedRect(
                    handle: handle,
                    startRect: startGlobal,
                    startPoint: startPoint,
                    point: point,
                    minSize: minAnnotation
                )
                // Annotate marks may live outside the selection — don't clamp into the blue rect.
                next.mapBoundingRect(to: toLocal(resizedGlobal))
            }
            updateAnnotation(id: id) { $0.payload = next.payload }
            updateHighlight(showHandles: true)

        case .annotateEndpoint(let id, let endpoint, let start):
            let local = toLocal(point)
            var next = start
            switch endpoint {
            case .start:
                if NSEvent.modifierFlags.contains(.shift) {
                    next.arrowStart = snappedArrowPoint(from: start.arrowEnd, toward: local)
                } else {
                    next.arrowStart = local
                }
            case .end:
                if NSEvent.modifierFlags.contains(.shift) {
                    next.arrowEnd = snappedArrowPoint(from: start.arrowStart, toward: local)
                } else {
                    next.arrowEnd = local
                }
            }
            updateAnnotation(id: id) { $0.payload = next.payload }
            updateHighlight(showHandles: true)
        }
    }

    func handleMouseUp(at point: CGPoint) {
        defer {
            dragKind = nil
            pendingWindowPick = nil
            textChromeDragStartFrame = nil
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
                setOverlayCursorMode(.selectingPlus)
                return
            }
            currentRect = rect
            enterRefineOrAutoConfirm()

        case .refining:
            switch dragKind {
            case .annotateDraw:
                if let draft = draftAnnotation {
                    draftAnnotation = nil
                    if isDraftWorthKeeping(draft) {
                        let ann = finalizedDraft(draft)
                        annotationHistory.commit { doc in
                            doc.marks.append(ann)
                            // Pencil / freehand mosaic / marker / eraser: no auto-select. Region: select for resize chrome.
                            doc.selectedID = (ann.isPencil || ann.isMosaicStroke || ann.isMarkerStroke
                                || ann.isEraserStroke)
                                ? nil : ann.id
                        }
                        refreshHistoryChrome()
                    }
                }
            case .annotateMove, .annotateResize, .annotateEndpoint:
                annotationHistory.endGesture()
                refreshHistoryChrome()
            default:
                break
            }

            // Text / step: click-to-place / click-to-re-edit when drag stayed tiny.
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
                    } else if annotateTool == .step {
                        placeStep(at: candidate.start)
                    }
                }
            }

            updateHighlight(showHandles: true)
            repositionToolbar()
            updateOverlayCursor(at: point)
        }
    }
}
