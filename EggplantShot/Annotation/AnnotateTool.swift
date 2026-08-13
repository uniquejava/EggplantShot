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
}
