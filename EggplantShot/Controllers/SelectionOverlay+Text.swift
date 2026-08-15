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

    /// **I** (Insert): arm text tool; if arming (not disarming) and the pointer is
    /// not over the toolbar, place + edit at the cursor (toolbar tap stays click-to-place).
    func armTextToolFromHotkey() {
        if annotateTool == .text {
            toggleRefineTool(.text)
            return
        }
        if let toolbar {
            toolbar.selectTool(.text)
        } else {
            setAnnotateTool(.text)
        }
        let point = NSEvent.mouseLocation
        if toolbar?.containsGlobalPoint(point) == true { return }
        placeAndEditText(at: point)
    }

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
        tv.font = ann.textStyle.makeFont()
        tv.textColor = ann.textStyle.color
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        // Only the explicit “background” style toggle fills behind glyphs.
        if ann.textStyle.hasBackground {
            tv.drawsBackground = true
            tv.backgroundColor = ContrastChrome.textPlate(behind: ann.textStyle.color)
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

    func applyTextStyleToEditor(_ style: TextStyle) {
        guard let tv = textEditor else { return }
        tv.font = style.makeFont()
        tv.textColor = style.color
        if style.hasBackground {
            tv.drawsBackground = true
            tv.backgroundColor = ContrastChrome.textPlate(behind: style.color)
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

    /// Hairline + caret: white on dark, black on light (not the palette / text color).
    func applyTextChromeContrast(style: TextStyle, globalPoint: CGPoint) {
        let color = ContrastChrome.textHairline(
            style: style,
            freezeLuminance: freezeLuminance(at: globalPoint)
        )
        textChromeView?.strokeColor = color
        textEditor?.insertionPointColor = color
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
