import AppKit

// MARK: - Overlay panels

final class SelectionPanel: NSPanel {
    let screenFrame: CGRect
    private let overlayView: SelectionOverlayNSView

    /// Refine / annotate: AppKit asks the view to update; forward to the controller.
    var onCursorUpdate: (() -> Void)? {
        get { overlayView.onCursorUpdate }
        set { overlayView.onCursorUpdate = newValue }
    }

    /// Selecting: AppKit cursor rects. Refining: controller hit-tests via `onCursorUpdate`.
    var cursorMode: SelectionOverlayNSView.CursorMode {
        get { overlayView.cursorMode }
        set { overlayView.cursorMode = newValue }
    }

    init(screen: NSScreen, freezeImage: NSImage?) {
        self.screenFrame = screen.frame
        self.overlayView = SelectionOverlayNSView(
            frame: CGRect(origin: .zero, size: screen.frame.size),
            freezeImage: freezeImage
        )

        // Must be able to become key so cursor rects apply (Terminal otherwise keeps I-beam).
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        level = .screenSaver
        // Opaque when frozen so live desktop cannot show through.
        isOpaque = freezeImage != nil
        backgroundColor = freezeImage != nil ? .black : .clear
        applySharedChrome()
    }

    /// Pin-edit lid: a transparent panel over a pinned bitmap that draws marks and nothing else.
    /// `frame` is Cocoa global and plays the part `screenFrame` plays for a capture panel — the
    /// panel's own rect in global space, which is all `setSelection` and the text editor need. It is
    /// deliberately larger than the bitmap so a text mark's field editor can grow past the edge, the
    /// way it can over the freeze; `SelectionOverlayNSView.hitTest` passes those margins through.
    /// `.nonactivatingPanel` because editing a pin must not pull focus off the frontmost app.
    init(pinEditFrame frame: CGRect, image: NSImage) {
        self.screenFrame = frame
        self.overlayView = SelectionOverlayNSView(
            frame: CGRect(origin: .zero, size: frame.size),
            freezeImage: nil
        )

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Above pins (`.statusBar`), below the toolbar this session shows.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        overlayView.pinEditImage = image
        overlayView.cursorMode = .controllerDriven
        applySharedChrome()
    }

    private func applySharedChrome() {
        // Must be able to become key so cursor rects apply (Terminal otherwise keeps I-beam).
        becomesKeyOnlyIfNeeded = false
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = overlayView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(becameKey),
            name: NSWindow.didBecomeKeyNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// After AppKit’s activation cursor reset, reinstall our rects.
    @objc private func becameKey() {
        invalidateCursorRects(for: overlayView)
    }

    func setSelection(
        _ globalRect: CGRect,
        showHandles: Bool,
        handleVisualSize: CGFloat,
        annotations: [Annotation],
        draftAnnotation: Annotation?,
        selectedAnnotation: Annotation?,
        annotationHandleSize: CGFloat,
        playbackImage: NSImage?,
        editingAnnotationID: UUID?,
        hoveredTextID: UUID?,
        hoveredPaintRegionID: UUID? = nil,
        showSolidMarkerRegionBorder: Bool = false,
        hideTextCornerBadges: Bool = false,
        hiddenMagnifierSourceIDs: Set<UUID> = []
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
        overlayView.editingAnnotationID = editingAnnotationID
        overlayView.hoveredTextID = hoveredTextID
        overlayView.hoveredPaintRegionID = hoveredPaintRegionID
        overlayView.showSolidMarkerRegionBorder = showSolidMarkerRegionBorder
        overlayView.hideTextCornerBadges = hideTextCornerBadges
        overlayView.hiddenMagnifierSourceIDs = hiddenMagnifierSourceIDs
        overlayView.needsDisplay = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
