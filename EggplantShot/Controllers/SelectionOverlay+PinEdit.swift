import AppKit

// Pin-edit: run the annotate surface over a pinned bitmap in place (Snipaste “Show toolbar”).
//
// Nothing about the tools is re-implemented here. The gesture handlers in `SelectionOverlay+Mouse`
// take global screen points and mark geometry is a plain offset from `currentRect`, so pointing
// `currentRect` at the pin's bitmap and hosting a transparent lid over it is the whole trick. What
// this file adds is the lid, the session's start / end, and the confirm semantics a pin needs.

/// What a pin-edit session was opened on. Cleared by `tearDownOverlays`.
struct PinEditContext {
    let itemID: UUID
    /// The bitmap being annotated; also what mosaic / marker / magnifier sample.
    let image: NSImage
    /// Document the session opened with — what ✕ reverts to.
    let startDocument: AnnotationDocument
}

/// How a pin-edit session ended. Copy / Save / OCR hand the baked bitmap off and the pin closes,
/// exactly as confirming a capture does; Apply is the one that leaves a pin behind.
enum PinEditOutcome {
    case applied(AnnotationDocument)
    case discarded
    case copied(NSImage)
    case saved(NSImage)
    case ocr(text: String)
}

@MainActor
extension SelectionOverlayController {
    /// Room around the bitmap for a text mark's field editor to grow into. The margins are
    /// click-through, so a big lid costs nothing to the windows underneath.
    private static let pinEditLidMargin: CGFloat = 200

    /// Annotate `image`, which is already on screen at `imageRect` (Cocoa global). Returns when the
    /// user applies, discards, or hands the result off to the clipboard / a file / OCR.
    func beginPinEdit(
        itemID: UUID,
        image: NSImage,
        imageRect: CGRect,
        document: AnnotationDocument = AnnotationDocument()
    ) async -> PinEditOutcome {
        tearDownOverlays()
        // No `historyStore` on a pin-edit controller, which is what leaves `,` / `.` inert.
        primaryAction = .pin
        skipsRefine = false
        pinEdit = PinEditContext(itemID: itemID, image: image, startDocument: document)
        currentRect = imageRect
        annotationHistory.reset(to: document)
        phase = .refining

        return await withCheckedContinuation { continuation in
            self.pinEditContinuation = continuation
            self.showPinEditLid(image: image, imageRect: imageRect)
        }
    }

    private func showPinEditLid(image: NSImage, imageRect: CGRect) {
        let panel = SelectionPanel(pinEditFrame: pinEditLidFrame(for: imageRect), image: image)
        panel.onCursorUpdate = { [weak self] in
            self?.reassertOverlayCursor()
        }
        panels.append(panel)
        panel.orderFrontRegardless()
        // Key so text marks can be typed into — but deliberately no `NSApp.activate`: annotating a
        // pin must not pull the user out of the app they were working in.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.contentView)

        installMonitors()
        updateHighlight(showHandles: false)
        showToolbar()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    /// The bitmap plus editor room, clipped to the display the pin sits on.
    private func pinEditLidFrame(for imageRect: CGRect) -> CGRect {
        let grown = imageRect.insetBy(dx: -Self.pinEditLidMargin, dy: -Self.pinEditLidMargin)
        let center = CGPoint(x: imageRect.midX, y: imageRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.first { $0.frame.intersects(imageRect) }
            ?? NSScreen.main
        guard let screen else { return grown }
        let clipped = grown.intersection(screen.frame)
        return clipped.isNull || clipped.isEmpty ? grown : clipped
    }

    /// Event routing: a pin-edit session owns the bitmap (plus handle slop), its toolbar, any live
    /// text editor, and any drag already under way. Everything else must reach the window below —
    /// same rule the lid's `hitTest` enforces for clicks that never reach a monitor.
    func pinEditOwnsPoint(_ point: CGPoint) -> Bool {
        guard pinEdit != nil else { return true }
        if dragKind != nil || isTextWheelGesture { return true }
        if let toolbar, toolbar.containsGlobalPoint(point) { return true }
        let slop = SelectionOverlayNSView.pinEditHitSlop
        if let editing = editingTextGlobalRect(),
           editing.insetBy(dx: -slop, dy: -slop).contains(point) {
            return true
        }
        return currentRect.insetBy(dx: -slop, dy: -slop).contains(point)
    }

    // MARK: - Ending the session

    /// Toolbar ✓ / Return / the Esc ladder's last rung: keep the marks, close the toolbar.
    func applyPinEdit() {
        endTextEditing(commit: true)
        let document = annotationHistory.document
        tearDownOverlays()
        finishPinEdit(.applied(document))
    }

    /// Toolbar ✕: throw away what this session drew; the pin goes back to how it was.
    func discardPinEdit() {
        endTextEditing(commit: false)
        tearDownOverlays()
        finishPinEdit(.discarded)
    }

    /// Copy / Save bake the pin as it looks and then close it, like confirming a capture.
    func confirmPinEdit(_ action: ConfirmAction) {
        guard pinEdit != nil else { return }
        switch action {
        case .pin:
            applyPinEdit()
        case .copy, .save:
            guard let baked = bakedPinEditImage() else { return }
            tearDownOverlays()
            finishPinEdit(action == .copy ? .copied(baked) : .saved(baked))
        }
    }

    /// Read the pin as it looks now (marks included), then close it — capture's OCR ends its session
    /// the same way. Recognition runs after teardown so the lid is gone while Vision works.
    func performPinEditOCR() {
        guard let baked = bakedPinEditImage() else { return }
        tearDownOverlays()
        Task { @MainActor in
            let text = await TextRecognizer.recognize(baked)
            self.finishPinEdit(.ocr(text: text))
        }
    }

    /// Commits any open editor first, so the mark being typed is part of the bake.
    private func bakedPinEditImage() -> NSImage? {
        guard let pinEdit else { return nil }
        endTextEditing(commit: true)
        return AnnotationCompositor.composite(annotationHistory.document.marks, onto: pinEdit.image)
    }

    func finishPinEdit(_ outcome: PinEditOutcome) {
        guard let pinEditContinuation else { return }
        self.pinEditContinuation = nil
        phase = .idle
        pinEditContinuation.resume(returning: outcome)
    }
}
