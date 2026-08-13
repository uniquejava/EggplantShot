import AppKit

// Arrow caps and endpoints.

enum ArrowCapStyle: Int, CaseIterable {
    case none = 0
    case bar = 2
    case circle = 3
    case diamond = 4
    /// Open chevron; shaft runs to the tip so line + wings stay connected.
    case openArrow = 5
    /// Kept for older prefs / disk; not shown in the menu (looked like `openArrow`).
    case openArrowWide = 6
    /// Filled triangle (default end cap). Raw value 1 kept for existing records.
    case arrow = 1
    case hollowArrow = 7

    /// Styles shown in the start / end dropdown (Snipaste order, no near-duplicate).
    static let menuCases: [ArrowCapStyle] = [
        .none, .bar, .circle, .diamond, .openArrow, .arrow, .hollowArrow,
    ]

    /// True for triangle / chevron arrowheads (used by double-ended Switch).
    var isArrowhead: Bool {
        switch self {
        case .openArrow, .openArrowWide, .arrow, .hollowArrow: return true
        default: return false
        }
    }
}

/// Start / end caps for an arrow mark.
struct ArrowCaps: Equatable {
    var start: ArrowCapStyle
    var end: ArrowCapStyle

    static let `default` = ArrowCaps(start: .none, end: .openArrow)

    /// Both ends plain (Switch “no arrow” row active).
    var isPlainLine: Bool { start == .none && end == .none }

    /// At least one end has an ornament (Switch “with arrow” row active).
    var hasCaps: Bool { !isPlainLine }

    static func plainLine() -> ArrowCaps { ArrowCaps(start: .none, end: .none) }
}

/// Which endpoint is being dragged while editing an arrow.
enum ArrowEndpoint: Equatable {
    case start
    case end
}

/// Stroke / fill / color used when drawing or editing an annotation.
