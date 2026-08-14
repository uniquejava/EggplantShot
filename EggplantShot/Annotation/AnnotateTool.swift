import AppKit

// Toolbar annotate tool selection.

/// Drawing tool selected on the refine toolbar. `.none` = refine selection only.
enum AnnotateTool: Equatable {
    case none
    case rectangle
    case arrow
    case pencil
    case marker
    case mosaic
    case text
    case step
    case magnifier
    case eraser

    /// Freehand / effect tools: existing marks draw-through so paint/erase isn't stolen by move hits.
    /// Hold ⌘ for temporary move (selected handles still work without ⌘).
    var drawsThroughMarks: Bool {
        switch self {
        case .pencil, .marker, .mosaic, .eraser:
            return true
        case .none, .rectangle, .arrow, .text, .step, .magnifier:
            return false
        }
    }
}
