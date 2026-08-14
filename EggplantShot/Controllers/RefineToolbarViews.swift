import AppKit
import CoreImage
import QuartzCore

// Toolbar root view (chrome widgets live in sibling files).

final class RefineToolbarView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
}
