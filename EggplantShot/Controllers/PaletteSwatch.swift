import AppKit

/// Fixed layout cell; chip starts small and scales up on hover.
/// Fill is drawn flush to the 1pt border (no CALayer inset gap).
final class PaletteSwatchControl: NSView {
    /// Snipaste @2x: 22 device-px → 11pt chip; 4px gap → 2pt (via stack spacing).
    static let cellSize: CGFloat = 11
    private static let restSize: CGFloat = 11
    private static let hoverSize: CGFloat = 13.5

    let swatch: PaletteColor
    let onPick: (PaletteColor) -> Void
    let chip = PaletteSwatchChip()
    var trackingArea: NSTrackingArea?

    init(swatch: PaletteColor, onPick: @escaping (PaletteColor) -> Void) {
        self.swatch = swatch
        self.onPick = onPick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.cellSize),
            heightAnchor.constraint(equalToConstant: Self.cellSize),
        ])

        chip.swatchColor = swatch.color
        addSubview(chip)
        layoutChip(size: Self.restSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        animateChip(size: Self.hoverSize)
    }

    override func mouseExited(with event: NSEvent) {
        animateChip(size: Self.restSize)
    }

    override func mouseDown(with event: NSEvent) {
        onPick(swatch)
    }

    func animateChip(size: CGFloat) {
        let origin = (Self.cellSize - size) / 2
        let target = CGRect(x: origin, y: origin, width: size, height: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.09
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            chip.animator().frame = target
        }
        chip.needsDisplay = true
    }

    func layoutChip(size: CGFloat) {
        let origin = (Self.cellSize - size) / 2
        chip.frame = CGRect(x: origin, y: origin, width: size, height: size)
        chip.needsDisplay = true
    }
}

final class PaletteSwatchChip: NSView {
    var swatchColor: NSColor = .black

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = max(1.75, bounds.width * 0.22)
        let fillPath = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        swatchColor.setFill()
        fillPath.fill()

        // Stroke on the same rect edge — no gap between fill and border.
        let strokePath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: max(radius - 0.5, 0.5),
            yRadius: max(radius - 0.5, 0.5)
        )
        strokePath.lineWidth = 1
        NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
        strokePath.stroke()
    }
}

