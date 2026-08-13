import AppKit

// MARK: - Text editing bridge

/// Routes `NSTextView` delegate callbacks back to the overlay controller.
@MainActor
final class TextEditingBridge: NSObject, NSTextViewDelegate {
    static let shared = TextEditingBridge()
    weak var owner: SelectionOverlayController?

    func textDidChange(_ notification: Notification) {
        owner?.resizeTextEditorToFit()
    }
}

/// Transparent host that paints a Snipaste-style white edit frame (no fill).
final class TextEditChromeView: NSView {
    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        // Dark halo for contrast on light screenshots.
        NSColor.black.withAlphaComponent(0.45).setStroke()
        let halo = NSBezierPath(rect: r)
        halo.lineWidth = 3
        halo.stroke()
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: r)
        border.lineWidth = 1.5
        border.stroke()
    }
}

/// Text mark field editor with an isolated undo stack (avoids poisoning the app-wide
/// `UndoManager` with `_undoRedoTextOperation:` targets that outlive the view).
final class AnnotationTextView: NSTextView {
    private let isolatedUndoManager = UndoManager()

    override var undoManager: UndoManager? { isolatedUndoManager }
    override var isOpaque: Bool { false }

    func clearIsolatedUndo() {
        isolatedUndoManager.removeAllActions()
    }
}
