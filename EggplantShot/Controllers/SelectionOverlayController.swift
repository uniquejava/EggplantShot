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
    /// After any Esc action, ignore further Esc until key-up (stops hold-repeat ladder walk).
    var suppressEscapeUntilKeyUp = false
    /// First Esc / Cancel with marks arms a second confirm; show a light tip until cleared.
    var escapeDiscardArmed = false
    var escapeHintPanel: NSPanel?
    var escapeHintHideWork: DispatchWorkItem?

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
    /// Snipaste hover: dashed outline over a non-selected rect / oval paint region
    /// (marker / mosaic / eraser).
    var hoveredPaintRegionID: UUID?
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
    /// Set by `placeAndEditText`, consumed by the next `endTextEditing`: this edit session is the
    /// *first* one for a just-placed mark, so its result belongs in the placement step rather than a
    /// step of its own. One-shot on purpose — "the mark is missing from the top snapshot" alone can be
    /// true again much later (delete the mark, then ⌘Z), which would fold an unrelated edit into it.
    var textAwaitingFirstEditID: UUID?
    /// Chrome frame at the start of a live-move while editing (panel-local).
    var textChromeDragStartFrame: CGRect?
    let textClickDragThreshold: CGFloat = 4
    /// Hide text corner badges only after the pointer has actually moved (not on mouse-down alone).
    var suppressTextCornerBadges = false
    /// Extra hit outside the text hairline so the border is easy to grab.
    let textBorderOutwardSlop: CGFloat = 2
    /// Scroll-wheel font-size gesture (coalesced like a slider drag).
    var isTextWheelGesture = false
    var textWheelScrollAccum: CGFloat = 0
    var textWheelResizeWork: DispatchWorkItem?
    /// Trackpad: ~2 pt of finger travel → one size step (pin zoom uses 12 because each
    /// step is already ±10%; 1–2 pt of type needs a much shorter flick).
    let textWheelPreciseThreshold: CGFloat = 2
    /// Points of `fontSize` per wheel notch / accumulated trackpad step.
    let textWheelPointsPerStep: Int = 2
    /// Ceiling on steps one scroll event may apply. Bounds a fast flick (which arrives as a single
    /// large-delta event) without discarding travel — the remainder carries to the next event.
    let textWheelMaxStepsPerEvent: Int = 2
    let textWheelGestureIdle: TimeInterval = 0.35

    /// Hold **Space** to temporarily drag-move the blue crop (open hand → closed hand while dragging).
    var spaceHeldForCropMove = false

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
        /// Top-right close badge on a text mark (Snipaste).
        case textClose(id: UUID)
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

    /// Crop selection → dismiss overlay → QR / OCR → hand text to `SnipController` (clipboard + sound).
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
        suppressEscapeUntilKeyUp = false
        clearEscapeDiscardHint()
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
        hoveredPaintRegionID = nil
        hoveredMagnifierLensIDs = []
        discardTextEditor()
        historyCursor = nil
        playbackBaseImage = nil
        phase = .idle
        // Don't NSCursor.arrow.set() — previous app restores its own cursor when it becomes key.
    }
}
