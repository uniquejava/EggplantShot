import AppKit

/// Drawing tool selected on the refine toolbar. `.none` = refine selection only.
enum AnnotateTool: Equatable {
    case none
    case rectangle
}

/// Stroke / color used when drawing or editing an annotation.
struct AnnotationStyle: Equatable {
    var strokeWidth: CGFloat
    var strokeColor: NSColor

    static let `default` = AnnotationStyle(
        strokeWidth: StrokeWidthOption.medium.points,
        strokeColor: PaletteColor.sky.color
    )
}

enum StrokeWidthOption: Int, CaseIterable {
    case hairline
    case thin
    case medium
    case thick

    var points: CGFloat {
        switch self {
        case .hairline: return 1.5
        case .thin: return 2.5
        case .medium: return 4
        case .thick: return 6
        }
    }

    /// Dot diameter shown in the sub-toolbar.
    var previewDiameter: CGFloat {
        switch self {
        case .hairline: return 3
        case .thin: return 5
        case .medium: return 7
        case .thick: return 10
        }
    }

    static func matching(_ width: CGFloat) -> StrokeWidthOption {
        allCases.min(by: { abs($0.points - width) < abs($1.points - width) }) ?? .medium
    }
}

/// Fixed Snipaste-like quick palette (4×4).
enum PaletteColor: Int, CaseIterable {
    case white, black, red, orange
    case yellow, lime, green, teal
    case cyan, sky, blue, indigo
    case purple, magenta, pink, brown

    var color: NSColor {
        switch self {
        case .white: return NSColor(calibratedWhite: 1, alpha: 1)
        case .black: return NSColor(calibratedWhite: 0.08, alpha: 1)
        case .red: return NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.22, alpha: 1)
        case .orange: return NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.15, alpha: 1)
        case .yellow: return NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.12, alpha: 1)
        case .lime: return NSColor(calibratedRed: 0.65, green: 0.9, blue: 0.2, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.22, green: 0.78, blue: 0.35, alpha: 1)
        case .teal: return NSColor(calibratedRed: 0.15, green: 0.72, blue: 0.68, alpha: 1)
        case .cyan: return NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.95, alpha: 1)
        case .sky: return NSColor(calibratedRed: 0.35, green: 0.72, blue: 0.98, alpha: 1)
        case .blue: return NSColor(calibratedRed: 0.18, green: 0.45, blue: 0.95, alpha: 1)
        case .indigo: return NSColor(calibratedRed: 0.35, green: 0.3, blue: 0.85, alpha: 1)
        case .purple: return NSColor(calibratedRed: 0.62, green: 0.28, blue: 0.9, alpha: 1)
        case .magenta: return NSColor(calibratedRed: 0.9, green: 0.25, blue: 0.7, alpha: 1)
        case .pink: return NSColor(calibratedRed: 0.98, green: 0.45, blue: 0.65, alpha: 1)
        case .brown: return NSColor(calibratedRed: 0.55, green: 0.35, blue: 0.2, alpha: 1)
        }
    }
}

/// One drawable mark. Geometry is in **selection-local** Cocoa points
/// (origin = selection bottom-left).
struct Annotation: Equatable {
    enum Kind: Equatable {
        case rectangle
    }

    let id: UUID
    var kind: Kind
    var rect: CGRect
    var style: AnnotationStyle

    init(id: UUID = UUID(), kind: Kind = .rectangle, rect: CGRect, style: AnnotationStyle) {
        self.id = id
        self.kind = kind
        self.rect = rect
        self.style = style
    }
}

enum AnnotationDrawing {
    /// Stroke annotations into the current graphics context. `rect` is already in context space.
    static func stroke(_ annotation: Annotation, in rect: CGRect) {
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = annotation.style.strokeWidth
        path.lineJoinStyle = .miter
        annotation.style.strokeColor.setStroke()
        path.stroke()
    }

    static func drawHandles(in rect: CGRect, size: CGFloat, accent: NSColor) {
        let centers: [CGPoint] = [
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
        ]
        for c in centers {
            let r = CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(rect: r).fill()
            accent.setStroke()
            let stroke = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
            stroke.lineWidth = 1
            stroke.stroke()
        }
    }
}

/// Cursors for annotate hit zones (draw / move / resize).
enum AnnotationCursors {
    /// White “＋” used inside the selection / annotation interior (draw mode).
    static let whitePlus: NSCursor = {
        let size: CGFloat = 24
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            let arm: CGFloat = 8
            let line = NSBezierPath()
            line.move(to: NSPoint(x: mid.x - arm, y: mid.y))
            line.line(to: NSPoint(x: mid.x + arm, y: mid.y))
            line.move(to: NSPoint(x: mid.x, y: mid.y - arm))
            line.line(to: NSPoint(x: mid.x, y: mid.y + arm))
            line.lineCapStyle = .round

            // Dark halo so it stays visible on light screenshots.
            line.lineWidth = 4
            NSColor.black.withAlphaComponent(0.55).setStroke()
            line.stroke()

            line.lineWidth = 2
            NSColor.white.setStroke()
            line.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()
}
