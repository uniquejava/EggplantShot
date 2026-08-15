import Foundation

/// The only undoable annotation state for an active snip session.
struct AnnotationDocument: Equatable {
    var marks: [Annotation] = []
    var selectedID: UUID?
}

/// Whole-document snapshot undo/redo. All mark mutations go through this type.
@MainActor
final class AnnotationHistory {
    private(set) var document: AnnotationDocument
    private var undoStack: [AnnotationDocument] = []
    private var redoStack: [AnnotationDocument] = []
    /// Baseline captured once at gesture start; live edits mutate `document` until `endGesture`.
    private var gestureBaseline: AnnotationDocument?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    /// Live edits are in `document` but no step exists yet — the window in which swapping the
    /// document (undo / redo / playback) would strand the gesture. Callers gate keys on this.
    var isGestureOpen: Bool { gestureBaseline != nil }

    init(document: AnnotationDocument = AnnotationDocument()) {
        self.document = document
    }

    /// The one definition of "worth an undo step": the **marks** differ. Selection is deliberately
    /// excluded — `select` is not a step, so an edit that only moved the selection isn't one either,
    /// no matter which entry point it arrived through.
    private func marksDiffer(from other: AnnotationDocument) -> Bool {
        other.marks != document.marks
    }

    /// Snapshot current doc, then mutate. Clears redo. No-op push if the marks are unchanged.
    ///
    /// If a gesture is open the mutation folds into it (live edit, no push) and `endGesture`
    /// collapses the whole run into one step. That's what keeps a slider drag off the stack:
    /// a toolbar slider fires its action on every tick, and each tick lands here.
    func commit(_ body: (inout AnnotationDocument) -> Void) {
        if gestureBaseline != nil {
            body(&document)
            return
        }
        let before = document
        body(&document)
        guard marksDiffer(from: before) else { return }
        undoStack.append(before)
        redoStack.removeAll()
    }

    /// Selection-only change (not an undo step).
    func select(_ id: UUID?) {
        document.selectedID = id
    }

    /// True when the newest step is the one that introduced `id` — the mark exists now and did not
    /// exist in that snapshot — so a follow-up edit to it may belong *in* that step.
    ///
    /// Necessary but **not sufficient**: this also goes true long afterwards if the mark is deleted and
    /// the delete undone (the top step is then an older baseline that predates the mark). Pair it with
    /// a one-shot "this is the first edit" token at the call site — see `textAwaitingFirstEditID`.
    func lastStepIntroduced(_ id: UUID) -> Bool {
        guard let last = undoStack.last else { return false }
        return document.marks.contains { $0.id == id }
            && !last.marks.contains { $0.id == id }
    }

    /// Fold a follow-up edit into the step already on top of the stack instead of pushing a new one.
    /// That snapshot is still the correct baseline, so nothing is pushed — and if the edit brings the
    /// document back to it, the step disappears (place a text, type nothing → no undo step at all).
    func amendLastStep(_ body: (inout AnnotationDocument) -> Void) {
        guard gestureBaseline == nil, !undoStack.isEmpty else {
            commit(body)
            return
        }
        body(&document)
        redoStack.removeAll()
        if let last = undoStack.last, !marksDiffer(from: last) {
            undoStack.removeLast()
        }
    }

    /// Drag/resize: remember baseline once; live-mutate `document` without pushing.
    ///
    /// Overlapping gestures would silently merge into one step (and the first `endGesture` would
    /// close the wrong one), so a second `beginGesture` closes the open one first. Defined behaviour
    /// beats a silent no-op: worst case is one extra undo step, never a lost or fused one.
    func beginGesture() {
        if gestureBaseline != nil {
            endGesture()
        }
        gestureBaseline = document
    }

    /// Live mutation between `beginGesture` and `endGesture` (no stack push).
    func mutateLive(_ body: (inout AnnotationDocument) -> Void) {
        body(&document)
    }

    /// If a live gesture is in progress, restore the baseline without pushing undo.
    func cancelGesture() {
        guard let baseline = gestureBaseline else { return }
        gestureBaseline = nil
        document = baseline
    }

    /// If the marks moved, push the baseline onto undo and clear redo — one step for the whole
    /// gesture, none if the drag ended where it started.
    func endGesture() {
        guard let baseline = gestureBaseline else { return }
        gestureBaseline = nil
        guard marksDiffer(from: baseline) else { return }
        undoStack.append(baseline)
        redoStack.removeAll()
    }

    func undo() {
        // A live gesture's edits were never a recorded step. Drop them rather than baking them into
        // the document behind the user's back — then move the stack.
        cancelGesture()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
    }

    func redo() {
        cancelGesture()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
    }

    /// Used by history restore / session teardown; clears stacks.
    func reset(to document: AnnotationDocument = AnnotationDocument()) {
        self.document = document
        undoStack.removeAll()
        redoStack.removeAll()
        gestureBaseline = nil
    }

    /// Keep marks glued to freeze pixels when the selection origin moves (crop move / resize).
    /// Updates the live document and every undo/redo snapshot so stacks stay consistent.
    /// `delta` is `oldOrigin - newOrigin` in screen points (added to selection-local coords).
    func rebaseForSelectionOriginDelta(_ delta: CGSize) {
        guard delta.width != 0 || delta.height != 0 else { return }
        translateAllMarks(in: &document, by: delta)
        for i in undoStack.indices {
            translateAllMarks(in: &undoStack[i], by: delta)
        }
        for i in redoStack.indices {
            translateAllMarks(in: &redoStack[i], by: delta)
        }
        if var baseline = gestureBaseline {
            translateAllMarks(in: &baseline, by: delta)
            gestureBaseline = baseline
        }
    }

    private func translateAllMarks(in doc: inout AnnotationDocument, by delta: CGSize) {
        for i in doc.marks.indices {
            doc.marks[i].translate(by: delta)
        }
    }
}
