import AppKit

// Toolbar annotate tool selection.

/// Drawing tool selected on the refine toolbar. `.none` = refine selection only.
enum AnnotateTool: Equatable {
    case none
    /// Move / select marks only (no draw). Hotkey **V**.
    case select
    case rectangle
    case arrow
    case pencil
    case marker
    case mosaic
    case text
    case step
    case magnifier
    case eraser

    /// Freehand / effect tools: existing marks always draw-through (move via **V**).
    /// Selected handles still work without switching tools.
    var drawsThroughMarks: Bool {
        switch self {
        case .pencil, .marker, .mosaic, .eraser:
            return true
        case .none, .select, .rectangle, .arrow, .text, .step, .magnifier:
            return false
        }
    }

    /// Modes that never create marks, so every mark is grabbable by its whole body.
    /// `.none` also lets a dimmed-area drag expand the crop; `.select` (V) keeps the crop still.
    var editsMarksOnly: Bool {
        switch self {
        case .none, .select:
            return true
        case .rectangle, .arrow, .pencil, .marker, .mosaic, .text, .step, .magnifier, .eraser:
            return false
        }
    }
}
