import AppKit

// Text editing + step place.

@MainActor
extension SelectionOverlayController {
    // MARK: - Text editing

    /// Next sequence number: max existing step + 1 (or 1 if none).
    func nextStepNumber() -> Int {
        let maxNumber = annotations.compactMap { ann -> Int? in
            guard ann.isStep else { return nil }
            return ann.stepNumber
        }.max() ?? 0
        return maxNumber + 1
    }

    func placeStep(at globalPoint: CGPoint) {
        let local = toLocal(globalPoint)
        let ann = Annotation(number: nextStepNumber(), center: local, stepStyle: stepStyle)
        annotationHistory.commit { doc in
            doc.marks.append(ann)
            doc.selectedID = ann.id
        }
        refreshHistoryChrome()
        updateHighlight(showHandles: true)
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    /// Placement is always a click — **I** / **T** only arm the tool, like every other tool letter
    /// and like tapping the toolbar's T. An earlier version dropped an editable box at the pointer
    /// the moment the key was pressed, which made text the one hotkey that mutated the document.
    func placeAndEditText(at globalPoint: CGPoint) {
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
        textAwaitingFirstEditID = ann.id
        refreshHistoryChrome()
        updateHighlight(showHandles: true)
        startTextEditing(id: ann.id)
    }

    func startTextEditing(id: UUID) {
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
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = true
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.containerSize = CGSize(
            width: TextBoxMetrics.unboundedExtent,
            height: TextBoxMetrics.unboundedExtent
        )
        // Style-dependent attributes go through the one shared path, never inline here — see
        // `applyStyleAttributes`. `resizeTextEditorToFit` below replaces the container size above
        // with the fitted box's inner width.
        applyStyleAttributes(ann.textStyle, to: tv)
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
        updateHoveredText(at: NSEvent.mouseLocation)
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func endTextEditing(commit: Bool) {
        guard let id = editingTextID else { return }
        // Consume the one-shot placement token whatever happens next, so a later edit to this same
        // mark can never fold into the placement step.
        let isFirstEditAfterPlacing = (textAwaitingFirstEditID == id)
        textAwaitingFirstEditID = nil
        // Amend only when the token agrees *and* the placement step is still the newest one (a border
        // drag mid-edit pushes its own step in between — then this is an ordinary edit).
        let amendsPlacement = isFirstEditAfterPlacing && annotationHistory.lastStepIntroduced(id)
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
            // Placed then abandoned: amending removes the mark *and* the placement step, so a text
            // the user never typed into leaves no undo step behind.
            let removeEmptyMark: (inout AnnotationDocument) -> Void = { doc in
                doc.marks.removeAll { $0.id == id }
                if doc.selectedID == id { doc.selectedID = nil }
            }
            if amendsPlacement {
                annotationHistory.amendLastStep(removeEmptyMark)
            } else {
                annotationHistory.commit(removeEmptyMark)
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
            let applyEdit: (inout AnnotationDocument) -> Void = { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].string = string
                doc.marks[idx].rect = newRect
                doc.selectedID = id
            }
            // Typing into a text mark that was *just placed* belongs in the placement step: otherwise
            // ⌘Z after typing leaves a stray empty mark on screen and needs a second press.
            if amendsPlacement {
                annotationHistory.amendLastStep(applyEdit)
            } else {
                annotationHistory.commit(applyEdit)
            }
            refreshHistoryChrome()
        } else {
            annotationHistory.select(id)
        }
        updateHighlight(showHandles: true)
    }

    func discardTextEditor() {
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
        textChromeDragStartFrame = nil
        TextEditingBridge.shared.owner = nil
    }

    /// The only place the field editor's **style-dependent** attributes are set. Both `startTextEditing`
    /// and `applyTextStyleToEditor` route through here, because when each set them inline the two drifted:
    /// the container inset was updated in one and not the other, and a value fed only from the restyle
    /// path meant a freshly-opened editor drew a hairline caret until some later resize happened to run.
    /// One-time wiring (delegate, resizability, first responder) stays in `startTextEditing`.
    func applyStyleAttributes(_ style: TextStyle, to tv: AnnotationTextView) {
        tv.font = style.makeFont()
        tv.textColor = style.color
        // Only the explicit “background” style toggle fills behind glyphs.
        tv.drawsBackground = style.hasBackground
        tv.backgroundColor = style.hasBackground
            ? ContrastChrome.textPlate(behind: style.color)
            : .clear
        tv.textContainerInset = NSSize(
            width: style.textHorizontalPadding,
            height: style.textVerticalPadding
        )
    }

    func applyTextStyleToEditor(_ style: TextStyle) {
        guard let tv = textEditor else { return }
        applyStyleAttributes(style, to: tv)
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
        let metrics = TextBoxMetrics(style: style, maxWidth: maxW)
        let size = tv.fittingSize(metrics)

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
        // Container = the box's **inner** width, not `maxW`. TextKit gives every line fragment that
        // ends in a newline a selection rect spanning the whole container width (only the last line
        // hugs its glyphs), so an oversized container made ⌘A on multi-line text paint the first
        // line's highlight out to the screen edge. Wrapping does not need the slack: `fittingSize`
        // measures unbounded to find the natural width and returns `maxWidth` when it has to wrap, so
        // the box width it just produced *is* the wrap decision — laying out at that width reproduces
        // it rather than second-guessing it.
        let inner = max(1, frame.width - metrics.horizontalPadding * 2)
        tv.textContainer?.containerSize = CGSize(
            width: inner,
            height: TextBoxMetrics.unboundedExtent
        )
        tv.textContainer?.widthTracksTextView = false
        chrome.needsDisplay = true
    }

    /// Hairline + caret: white on dark, black on light (not the palette / text color).
    func applyTextChromeContrast(style: TextStyle, globalPoint: CGPoint) {
        let color = ContrastChrome.textHairline(
            style: style,
            freezeLuminance: freezeLuminance(at: globalPoint)
        )
        textChromeView?.strokeColor = color
        textEditor?.insertionPointColor = color
    }

    /// One quick blink of the corner badges, acknowledging a badge press that changed nothing.
    /// Reuses the drag-suppression flag, so it touches no marks, no history, and not the field
    /// editor's first-responder status.
    func blinkTextCornerBadges() {
        guard textChromeView?.showsCornerBadges == true else { return }
        suppressTextCornerBadges = true
        textChromeView?.showsCornerBadges = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.editingTextID != nil else { return }
            self.suppressTextCornerBadges = false
            self.updateHoveredText(at: NSEvent.mouseLocation)
        }
    }

    /// Corner-drag resize of the mark currently being edited. Drives `fontSize` and lets the field
    /// editor re-fit (as the wheel does), anchored on the corner opposite `handle` so the un-dragged
    /// corner stays put. The editor is never closed — closing it is what used to delete a blank mark
    /// and leave a click-to-place behind, so the mark appeared to jump to the badge.
    ///
    /// One press stays live across the whole range: drag inward past the anchor and the scale crosses
    /// zero and grows again, so a single gesture sweeps max → min → max (Snipaste-style).
    func resizeEditingTextByDrag(
        handle: Handle,
        startRect: CGRect,
        startPoint: CGPoint,
        point: CGPoint,
        startStyle: TextStyle
    ) {
        let edges = handle.drivenEdges
        // Scale comes straight from the drag, deliberately *not* via `resizedRectKeepingAspect`: its
        // rect floors (`minAnnotation` = 4) pin a blank mark's 4.5pt-wide box the moment scale drops
        // below 0.889, which freezes the aspect-locked height and caps one whole drag at ~11% shrink
        // (72 → 64, release, 64 → 57, release …). Here the box is derived from `fontSize`, so
        // `fontSize` is the only thing that needs bounding.
        let anchorX = edges.x.opposite.coordinate(min: startRect.minX, max: startRect.maxX)
        let anchorY = edges.y.opposite.coordinate(min: startRect.minY, max: startRect.maxY)
        let cornerX = edges.x.coordinate(min: startRect.minX, max: startRect.maxX)
        let cornerY = edges.y.coordinate(min: startRect.minY, max: startRect.maxY)
        let baseX = cornerX - anchorX
        let baseY = cornerY - anchorY
        let baseLengthSquared = baseX * baseX + baseY * baseY
        guard baseLengthSquared > 0.0001 else { return }
        let dragX = baseX + (point.x - startPoint.x)
        let dragY = baseY + (point.y - startPoint.y)
        // `abs` is what lets the gesture continue past the minimum instead of dead-ending there:
        // crossing the anchor flips the projection's sign, and the magnitude grows again.
        let scale = abs((dragX * baseX + dragY * baseY) / baseLengthSquared)

        var style = startStyle
        style.fontSize = TextStyle.clampFontSize(startStyle.fontSize * scale)
        let current = annotations.first(where: { $0.id == editingTextID })?.textStyle.fontSize
        guard abs(style.fontSize - (current ?? startStyle.fontSize)) > 0.01 else { return }

        applyTextStyle(
            style,
            persist: false,
            editingAnchor: (x: edges.x.opposite, y: edges.y.opposite)
        )
        toolbar?.syncTextStyle(style)
    }

    // MARK: - Scroll-wheel font size

    /// Editing mark, else the text under the pointer, else the selected text.
    func textWheelResizeTarget(at point: CGPoint) -> UUID? {
        if let id = editingTextID { return id }
        if let id = textMarkID(at: point) { return id }
        if let id = selectedAnnotationID,
           annotations.first(where: { $0.id == id })?.isText == true {
            return id
        }
        return nil
    }

    /// `true` when the event was consumed (including a trackpad tick that only accumulated).
    @discardableResult
    func handleTextScrollWheel(_ event: NSEvent) -> Bool {
        guard phase == .refining, dragKind == nil else { return false }
        guard let id = textWheelResizeTarget(at: NSEvent.mouseLocation) else { return false }
        if annotationHistory.isGestureOpen, !isTextWheelGesture { return false }

        let steps = textFontSizeWheelSteps(from: event)
        guard steps != 0 else { return true }

        if selectedAnnotationID != id {
            annotationHistory.select(id)
            if let ann = annotations.first(where: { $0.id == id }) {
                syncToolbar(from: ann)
            }
        }

        var style = annotations.first(where: { $0.id == id })?.textStyle ?? textStyle
        let before = style.fontSize
        style.nudgeFontSize(by: steps * textWheelPointsPerStep)
        guard abs(style.fontSize - before) > 0.01 else { return true }
        beginTextWheelResizeIfNeeded()
        applyTextStyle(style)
        toolbar?.syncTextStyle(style)
        return true
    }

    func textFontSizeWheelSteps(from event: NSEvent) -> Int {
        // Inertia after a flick would keep resizing on its own — only real finger / wheel motion counts.
        guard event.momentumPhase == [] else { return 0 }
        let dy = event.scrollingDeltaY
        guard dy != 0 else { return 0 }
        guard event.hasPreciseScrollingDeltas else { return dy > 0 ? 1 : -1 }

        textWheelScrollAccum += dy
        // Spend the accumulated travel, but no more than `textWheelMaxStepsPerEvent` per event: a
        // fast flick arrives as one large-delta event, and draining it whole jumped ~20 pt (40 → 60).
        // Keeping the remainder is what makes normal scrolling responsive — an earlier version zeroed
        // it, which silently threw away most of a Magic Mouse / trackpad gesture's travel.
        var steps = 0
        var applied = 0
        while applied < textWheelMaxStepsPerEvent,
              abs(textWheelScrollAccum) >= textWheelPreciseThreshold {
            if textWheelScrollAccum > 0 {
                textWheelScrollAccum -= textWheelPreciseThreshold
                steps += 1
            } else {
                textWheelScrollAccum += textWheelPreciseThreshold
                steps -= 1
            }
            applied += 1
        }
        // Never bank a backlog past one step's worth, or a flick that outran the cap would keep
        // stepping on later events after the fingers stopped.
        textWheelScrollAccum = min(
            textWheelPreciseThreshold,
            max(-textWheelPreciseThreshold, textWheelScrollAccum)
        )
        return steps
    }

    func beginTextWheelResizeIfNeeded() {
        if !isTextWheelGesture {
            annotationHistory.beginGesture()
            isTextWheelGesture = true
        }
        textWheelResizeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.endTextWheelResizeIfNeeded()
        }
        textWheelResizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + textWheelGestureIdle, execute: work)
    }

    func endTextWheelResizeIfNeeded() {
        textWheelResizeWork?.cancel()
        textWheelResizeWork = nil
        textWheelScrollAccum = 0
        guard isTextWheelGesture else { return }
        isTextWheelGesture = false
        annotationHistory.endGesture()
        refreshHistoryChrome()
    }

    func freezeLuminance(at globalPoint: CGPoint) -> CGFloat {
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
        return ContrastChrome.adjustedLuminance(
            luminance,
            point: globalPoint,
            selectionRect: currentRect
        )
    }

}
