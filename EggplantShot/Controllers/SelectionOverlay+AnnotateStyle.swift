import AppKit

// Annotate cursors, tool/style apply, undo/redo.

@MainActor
extension SelectionOverlayController {
    func updateOverlayCursor(at point: CGPoint) {
        switch phase {
        case .idle, .drawing:
            // AppKit cursor rects (`.selectingPlus`) own the white ＋.
            return
        case .refining:
            if annotateTool != .none {
                updateAnnotateCursor(at: point)
            } else {
                updateRefineCursor(at: point)
            }
        }
    }

    func setOverlayCursorMode(_ mode: SelectionOverlayNSView.CursorMode) {
        for panel in panels {
            panel.cursorMode = mode
        }
    }

    /// Re-apply hit-tested cursor after AppKit clears it (caret blink, cursor rect invalidation).
    func reassertOverlayCursor() {
        guard continuation != nil, !panels.isEmpty else { return }
        guard phase == .refining, dragKind == nil else { return }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    /// Selection-only refine: four-arrow move; resize arrows on border / outside octants.
    func updateRefineCursor(at point: CGPoint) {
        if let toolbar, toolbar.containsGlobalPoint(point) {
            NSCursor.arrow.set()
            return
        }
        if let handle = refineResizeHandle(at: point, allowOutsideExpand: true) {
            resizeCursor(for: handle).set()
        } else if currentRect.contains(point) {
            AnnotationCursors.move.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    func updateAnnotateCursor(at point: CGPoint) {
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
        case .arrowEndpoint:
            AnnotationCursors.move.set()
        case .border:
            AnnotationCursors.move.set()
        case .interior:
            NSCursor.iBeam.set()
        case .draw:
            // Border / handles only — outside octants keep the annotate cursor.
            if let handle = refineResizeHandle(at: point, allowOutsideExpand: false) {
                resizeCursor(for: handle).set()
            } else if annotateTool == .pencil {
                AnnotationCursors.pencilCrosshair(color: annotationStyle.strokeColor).set()
            } else if annotateTool == .mosaic {
                if mosaicDrawMode == .freehand {
                    AnnotationCursors.mosaicCrosshair(brushWidth: mosaicStyle.brushWidth).set()
                } else {
                    AnnotationCursors.whitePlus.set()
                }
            } else if annotateTool == .marker {
                if markerDrawMode == .freehand {
                    AnnotationCursors.mosaicCrosshair(brushWidth: markerStyle.brushWidth).set()
                } else {
                    AnnotationCursors.whitePlus.set()
                }
            } else if annotateTool == .eraser {
                if eraserDrawMode == .freehand {
                    // Temporary: same tip as mosaic. Concentric-ring tip deferred.
                    AnnotationCursors.mosaicCrosshair(brushWidth: eraserStyle.brushWidth).set()
                } else {
                    AnnotationCursors.whitePlus.set()
                }
            } else if annotateTool == .text {
                NSCursor.iBeam.set()
            } else if annotateTool == .step {
                AnnotationCursors.stepBadge(number: nextStepNumber(), style: stepStyle).set()
            } else {
                AnnotationCursors.whitePlus.set()
            }
        case .outside:
            NSCursor.arrow.set()
        }
    }

    func resizeCursor(for handle: Handle) -> NSCursor {
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

    func setAnnotateTool(_ tool: AnnotateTool) {
        if tool != annotateTool {
            endTextEditing(commit: true)
        }
        annotateTool = tool
        if tool == .none {
            annotationHistory.select(nil)
        } else if tool == .pencil || tool == .arrow, annotationStyle.isFilled {
            // Pencil / arrow have no fill; fall back to last stroke width.
            annotationStyle.isFilled = false
            AnnotationPrefs.save(style: annotationStyle, kind: annotationKind)
        }
        // Magnifier tool always shows sources; leaving it may need hover recompute.
        hoveredMagnifierLensIDs = magnifierLensIDs(containing: NSEvent.mouseLocation)
        toolbar?.setAnnotateTool(tool)
        updateHighlight(showHandles: true)
        repositionToolbar()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyStyle(_ style: AnnotationStyle) {
        var next = style
        if annotateTool == .pencil || annotateTool == .arrow {
            next.isFilled = false
        }
        annotationStyle = next
        AnnotationPrefs.save(style: next, kind: annotationKind)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           !selected.isText, !selected.isMosaic, !selected.isMarker, !selected.isEraser,
           !selected.isStep, !selected.isMagnifier {
            var applied = next
            // Don't push fill onto a pencil / arrow mark.
            if selected.isPencil || selected.isArrow {
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

    func applyTextStyle(_ style: TextStyle) {
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

    func applyMosaicStyle(_ style: MosaicStyle) {
        var next = style
        next.clamp()
        mosaicStyle = next
        AnnotationPrefs.saveMosaicStyle(next)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           selected.isMosaic {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].mosaicStyle = next
            }
            updateHighlight(showHandles: true)
            refreshHistoryChrome()
        }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyMosaicDrawMode(_ mode: MosaicDrawMode) {
        mosaicDrawMode = mode
        AnnotationPrefs.saveMosaicDrawMode(mode)
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyMarkerStyle(_ style: MarkerStyle) {
        var next = style
        next.clamp()
        markerStyle = next
        AnnotationPrefs.saveMarkerStyle(next)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           selected.isMarker {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].markerStyle = next
            }
            updateHighlight(showHandles: true)
            refreshHistoryChrome()
        }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyMarkerDrawMode(_ mode: MosaicDrawMode) {
        markerDrawMode = mode
        AnnotationPrefs.saveMarkerDrawMode(mode)
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyEraserStyle(_ style: EraserStyle) {
        var next = style
        next.clamp()
        eraserStyle = next
        AnnotationPrefs.saveEraserStyle(next)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           selected.isEraser {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].eraserStyle = next
            }
            updateHighlight(showHandles: true)
            refreshHistoryChrome()
        }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyEraserDrawMode(_ mode: MosaicDrawMode) {
        eraserDrawMode = mode
        AnnotationPrefs.saveEraserDrawMode(mode)
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyStepStyle(_ style: StepStyle) {
        var next = style
        next.clamp()
        stepStyle = next
        StepAnnotationPrefs.save(next)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           selected.isStep {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].stepStyle = next
            }
            updateHighlight(showHandles: true)
            refreshHistoryChrome()
        }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyMagnifier(kind: ShapeKind, style: MagnifierStyle) {
        var next = style
        next.clamp()
        let previousScale = magnifierStyle.scale
        let scaleChanged = abs(next.scale - previousScale) > 0.0005
        magnifierKind = kind
        magnifierStyle = next
        MagnifierAnnotationPrefs.save(kind: kind, style: next)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           selected.isMagnifier {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].magnifierKind = kind
                doc.marks[idx].magnifierStyle = next
                if scaleChanged {
                    let source = doc.marks[idx].magnifierSource
                    let lens = doc.marks[idx].magnifierLens
                    let scaled = Annotation.scaledMagnifierLens(
                        source: source,
                        scale: next.scale,
                        center: CGPoint(x: lens.midX, y: lens.midY)
                    )
                    doc.marks[idx].mapMagnifierPart(.lens, to: scaled)
                }
            }
            updateHighlight(showHandles: true)
            refreshHistoryChrome()
        }
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func applyKind(_ kind: ShapeKind) {
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

    func applyArrowCaps(_ caps: ArrowCaps) {
        arrowCaps = caps
        AnnotationPrefs.saveArrowCaps(caps)
        if let id = selectedAnnotationID,
           let selected = annotations.first(where: { $0.id == id }),
           selected.isArrow {
            annotationHistory.commit { doc in
                guard let idx = doc.marks.firstIndex(where: { $0.id == id }) else { return }
                doc.marks[idx].arrowCaps = caps
            }
            updateHighlight(showHandles: true)
            refreshHistoryChrome()
        }
    }

    func performUndo() {
        guard annotationHistory.canUndo else { return }
        annotationHistory.undo()
        syncAfterHistoryChange()
    }

    func performRedo() {
        guard annotationHistory.canRedo else { return }
        annotationHistory.redo()
        syncAfterHistoryChange()
    }

    func syncAfterHistoryChange() {
        endTextEditing(commit: false)
        if let id = selectedAnnotationID,
           let ann = annotations.first(where: { $0.id == id }) {
            syncToolbar(from: ann)
        }
        updateHighlight(showHandles: true)
        refreshHistoryChrome()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

    func refreshHistoryChrome() {
        toolbar?.setHistoryAvailability(
            canUndo: annotationHistory.canUndo,
            canRedo: annotationHistory.canRedo
        )
    }

}
