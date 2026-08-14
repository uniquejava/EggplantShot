import AppKit

@MainActor
extension SelectionOverlayController {
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
                if self.suppressEscapeUntilKeyUp || event.isARepeat {
                    return nil
                }
                self.handleEscapeKey()
                // One ladder step per press — hold must not walk tool→deselect→discard.
                self.suppressEscapeUntilKeyUp = true
                return nil
            }
            self.clearEscapeDiscardHint()
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
                    // ⌘S still saves the snip; ⌘C stays with the field editor (copy text).
                    if chars == "s" {
                        self.confirm(.save)
                        return nil
                    }
                }
                return event
            }
            // Hold Space: temporary crop move (not while typing in a text mark).
            if self.phase == .refining,
               event.keyCode == 49,
               event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                if !event.isARepeat {
                    self.setSpaceHeldForCropMove(true)
                }
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
                // ⌘Z undo; ⇧⌘Z / ⌘Y redo; ⌘S save; ⌘C copy.
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
                    if chars == "s" {
                        self.confirm(.save)
                        return nil
                    }
                    if chars == "c" {
                        self.confirm(.copy)
                        return nil
                    }
                }
                // Letter tool / action hotkeys (no ⌘/⌃/⌥). Toggle like toolbar taps.
                if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                   self.dragKind == nil,
                   let chars = event.charactersIgnoringModifiers?.lowercased(),
                   chars.count == 1,
                   let ch = chars.first {
                    switch ch {
                    case "v": self.toggleRefineTool(.select); return nil
                    case "a": self.toggleRefineTool(.rectangle); return nil
                    case "s": self.toggleRefineTool(.arrow); return nil
                    case "d": self.toggleRefineTool(.pencil); return nil
                    case "f": self.toggleRefineTool(.marker); return nil
                    case "m": self.toggleRefineTool(.mosaic); return nil
                    case "i": self.armTextToolFromHotkey(); return nil
                    case "n": self.toggleRefineTool(.step); return nil
                    case "e": self.toggleRefineTool(.eraser); return nil
                    case "p": self.confirm(.pin); return nil
                    case "o": self.performOCR(); return nil
                    case "r":
                        if self.applyPaletteHotkey(.red) { return nil }
                    case "g":
                        if self.applyPaletteHotkey(.green) { return nil }
                    case "b":
                        if self.applyPaletteHotkey(.cyan) { return nil }
                    default: break
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

        if let mon = NSEvent.addLocalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            if event.keyCode == 53 {
                self?.suppressEscapeUntilKeyUp = false
            }
            if event.keyCode == 49 {
                self?.setSpaceHeldForCropMove(false)
            }
            return event
        }) {
            eventMonitors.append(mon)
        }

        // Space may be released while another app is key — keep crop-pan state in sync.
        if let mon = NSEvent.addGlobalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            if event.keyCode == 49 {
                self?.setSpaceHeldForCropMove(false)
            }
        }) {
            eventMonitors.append(mon)
        }

        // ⌘ up/down: refresh move-vs-draw cursor for step tool (⌘ moves foreign marks).
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

    /// Esc ladder while capturing: end text → abort drag → disarm tool → deselect mark.
    /// With marks still present: first Esc shows a tip; second Esc discards (toolbar ✕ still immediate).
    func handleEscapeKey() {
        if editingTextID != nil {
            clearEscapeDiscardHint()
            endTextEditing(commit: true)
            return
        }
        if phase == .refining {
            if dragKind != nil || draftAnnotation != nil {
                clearEscapeDiscardHint()
                cancelInProgressRefineDrag()
                return
            }
            if annotateTool != .none {
                clearEscapeDiscardHint()
                setAnnotateTool(.none)
                return
            }
            if selectedAnnotationID != nil {
                clearEscapeDiscardHint()
                annotationHistory.select(nil)
                updateHighlight(showHandles: true)
                updateOverlayCursor(at: NSEvent.mouseLocation)
                return
            }
            if !annotations.isEmpty {
                if escapeDiscardArmed {
                    clearEscapeDiscardHint()
                    tearDownOverlays()
                    finish(.cancelled)
                    return
                }
                armEscapeDiscardHint()
                return
            }
        }
        clearEscapeDiscardHint()
        tearDownOverlays()
        finish(.cancelled)
    }

    /// Light tip: press Esc again to discard. Arms a one-shot second Esc.
    func armEscapeDiscardHint() {
        escapeDiscardArmed = true
        showEscapeDiscardHint()
        escapeHintHideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.clearEscapeDiscardHint()
        }
        escapeHintHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: work)
    }

    func clearEscapeDiscardHint() {
        escapeDiscardArmed = false
        escapeHintHideWork?.cancel()
        escapeHintHideWork = nil
        escapeHintPanel?.orderOut(nil)
        escapeHintPanel?.close()
        escapeHintPanel = nil
    }

    func showEscapeDiscardHint() {
        escapeHintPanel?.orderOut(nil)
        escapeHintPanel?.close()

        let label = NSTextField(labelWithString: L10n.tr("Press Esc again to discard"))
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.lineBreakMode = .byClipping
        label.sizeToFit()

        let padX: CGFloat = 10
        let padY: CGFloat = 6
        let contentSize = NSSize(
            width: ceil(label.frame.width) + padX * 2,
            height: ceil(label.frame.height) + padY * 2
        )
        label.frame = NSRect(
            x: padX,
            y: padY,
            width: contentSize.width - padX * 2,
            height: contentSize.height - padY * 2
        )

        let chrome = NSView(frame: NSRect(origin: .zero, size: contentSize))
        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = NSColor.white.cgColor
        chrome.layer?.cornerRadius = 6
        chrome.layer?.borderWidth = 0.5
        chrome.layer?.borderColor = NSColor(calibratedWhite: 0.75, alpha: 1).cgColor
        chrome.addSubview(label)

        let tip = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tip.isOpaque = false
        tip.backgroundColor = .clear
        tip.hasShadow = true
        tip.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        tip.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        tip.hidesOnDeactivate = false
        tip.isReleasedWhenClosed = false
        tip.ignoresMouseEvents = true
        tip.contentView = chrome

        // Center just above the selection (or toolbar if the rect is near the bottom).
        var origin = CGPoint(
            x: currentRect.midX - contentSize.width / 2,
            y: currentRect.maxY + 10
        )
        if let screen = panels.first(where: { $0.screenFrame.intersects(currentRect) })?.screen
            ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.y + contentSize.height > visible.maxY - 4 {
                origin.y = currentRect.minY - contentSize.height - 10
            }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - contentSize.width - 4)
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - contentSize.height - 4)
        }
        tip.setFrameOrigin(origin)
        tip.orderFrontRegardless()
        escapeHintPanel = tip
    }

    /// Drop an unfinished refine gesture without committing (Esc mid-drag).
    func cancelInProgressRefineDrag() {
        switch dragKind {
        case .annotateDraw:
            draftAnnotation = nil
        case .annotateMove, .annotateResize, .annotateEndpoint:
            annotationHistory.cancelGesture()
        case .move(let startRect, _):
            setSelectionRect(startRect)
        case .resize(_, let startRect, _):
            setSelectionRect(startRect)
        case .expand(_, let baseRect):
            setSelectionRect(baseRect)
        case .draw, .none:
            break
        }
        dragKind = nil
        draftAnnotation = nil
        textClickCandidate = nil
        textChromeDragStartFrame = nil
        updateHighlight(showHandles: true)
        repositionToolbar()
        refreshHistoryChrome()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    /// Hold **Space** → temporary blue-crop drag (cursor updates on key alone).
    func setSpaceHeldForCropMove(_ held: Bool) {
        guard spaceHeldForCropMove != held else { return }
        spaceHeldForCropMove = held
        // Keep closed-hand while an in-flight crop drag finishes after Space release.
        if case .move = dragKind { return }
        guard phase == .refining, dragKind == nil else { return }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    /// ⌘ while step tool is armed: temporary move of foreign marks (cursor updates on key alone).
    func handleAnnotateModifierFlagsChanged() {
        guard phase == .refining, annotateTool == .step, dragKind == nil else { return }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func removeMonitors() {
        spaceHeldForCropMove = false
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
        clearEscapeDiscardHint()
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
        // Hold Space: drag the blue crop (temporary; ignores annotate hits).
        if spaceHeldForCropMove {
            if editingTextID != nil {
                endTextEditing(commit: true)
            }
            annotationHistory.select(nil)
            textClickCandidate = nil
            if currentRect.contains(point) {
                dragKind = .move(startRect: currentRect, startPoint: point)
                NSCursor.closedHand.set()
                updateHighlight(showHandles: true)
            }
            return
        }

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
                if annotateTool == .select {
                    annotationHistory.select(nil)
                    updateHighlight(showHandles: true)
                    return
                }
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

        // Selection refine (no annotate tool): border / handles resize; outside expands.
        // Interior does not move the crop — rare, not undoable, and easy to hit by accident
        // after toggling Move (V) off.
        annotationHistory.select(nil)
        if beginSelectionEdgeDragIfNeeded(at: point, allowOutsideExpand: true) {
            return
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
