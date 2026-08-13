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

    init(document: AnnotationDocument = AnnotationDocument()) {
        self.document = document
    }

    /// Snapshot current doc, then mutate. Clears redo. No-op push if unchanged.
    func commit(_ body: (inout AnnotationDocument) -> Void) {
        gestureBaseline = nil
        let before = document
        body(&document)
        guard document != before else { return }
        undoStack.append(before)
        redoStack.removeAll()
    }

    /// Selection-only change (not an undo step).
    func select(_ id: UUID?) {
        document.selectedID = id
    }

    /// Drag/resize: remember baseline once; live-mutate `document` without pushing.
    func beginGesture() {
        if gestureBaseline == nil {
            gestureBaseline = document
        }
    }

    /// Live mutation between `beginGesture` and `endGesture` (no stack push).
    func mutateLive(_ body: (inout AnnotationDocument) -> Void) {
        body(&document)
    }

    /// If document ≠ baseline, push baseline onto undo and clear redo.
    func endGesture() {
        guard let baseline = gestureBaseline else { return }
        gestureBaseline = nil
        guard document != baseline else { return }
        undoStack.append(baseline)
        redoStack.removeAll()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        gestureBaseline = nil
        redoStack.append(document)
        document = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        gestureBaseline = nil
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
}
