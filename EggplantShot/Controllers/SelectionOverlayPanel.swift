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
        becomesKeyOnlyIfNeeded = false
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
