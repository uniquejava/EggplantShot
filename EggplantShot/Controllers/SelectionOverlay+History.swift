import AppKit

// Snip history playback (, / .).

@MainActor
extension SelectionOverlayController {
    // MARK: - History playback (, / .)

    func browseHistory(older: Bool) {
        // Quick-copy flow has no refine UI; history playback is for annotate sessions only.
        guard !skipsRefine else { return }
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

    func restoreRecord(_ record: SnipRecord) {
        endTextEditing(commit: false)
        dragKind = nil
        pendingWindowPick = nil
        hoveredWindowRect = nil
        draftAnnotation = nil
        textClickCandidate = nil
        hoveredTextID = nil
        hoveredPaintRegionID = nil
        hoveredMagnifierLensIDs = []
        annotateTool = .none
        let prefs = AnnotationPrefs.load()
        annotationStyle = prefs.style
        annotationKind = prefs.kind
        arrowCaps = AnnotationPrefs.loadArrowCaps()
        textStyle = TextAnnotationPrefs.load()
        setOverlayCursorMode(.controllerDriven)

        currentRect = record.selection
        clampRectToScreens()
        playbackBaseImage = record.baseImage
        annotationHistory.reset(to: record.document)

        phase = .refining
        updateHighlight(showHandles: true)
        showToolbar()
        refreshHistoryChrome()
        updateOverlayCursor(at: NSEvent.mouseLocation)
    }

}
