import AppKit
import CoreImage
import QuartzCore

// Toolbar chrome views (cards, palette, sliders, previews).

final class RefineToolbarView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
}

/// White rounded chrome card; Snipaste-like blue accent under the hovered tool button.
final class HoverChromeCard: NSView {
    private static let cornerRadius: CGFloat = 6
    private static let accentHeight: CGFloat = 2
    /// If the tool sits within this inset of a side, extend the bar into that rounded corner.
    private static let edgeExtendSlop: CGFloat = 10

    let chrome = NSView(frame: .zero)
    let accent = NSView(frame: .zero)
    var trackingArea: NSTrackingArea?
    private weak var hoveredButton: NSButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        translatesAutoresizingMaskIntoConstraints = false

        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = NSColor.white.cgColor
        chrome.layer?.cornerRadius = Self.cornerRadius
        chrome.layer?.masksToBounds = true
        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome)

        accent.wantsLayer = true
        accent.layer?.backgroundColor = NSColor.systemBlue.cgColor
        accent.alphaValue = 0
        // Frame-positioned under the hovered tool (not Auto Layout).
        accent.translatesAutoresizingMaskIntoConstraints = true
        chrome.addSubview(accent)

        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func installContent(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(child, positioned: .below, relativeTo: accent)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
            child.topAnchor.constraint(equalTo: chrome.topAnchor),
            child.bottomAnchor.constraint(equalTo: chrome.bottomAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Nonactivating toolbar panel — same as palette / mosaic slider.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        syncHover(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        syncHover(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredButton(nil)
    }

    override func layout() {
        super.layout()
        if let hoveredButton {
            positionAccent(under: hoveredButton, animated: false)
        }
    }

    func syncHover(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHoveredButton(toolButton(at: point))
    }

    func toolButton(at point: CGPoint) -> NSButton? {
        let local = chrome.convert(point, from: self)
        guard let hit = chrome.hitTest(local) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== chrome {
            if let button = current as? NSButton {
                return button
            }
            view = current.superview
        }
        return nil
    }

    func setHoveredButton(_ button: NSButton?) {
        if hoveredButton === button { return }
        hoveredButton = button
        if let button {
            positionAccent(under: button, animated: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().alphaValue = 0
            }
        }
    }

    func positionAccent(under button: NSButton, animated: Bool) {
        let buttonRect = button.convert(button.bounds, to: chrome)
        var x = buttonRect.minX
        var width = buttonRect.width
        let bounds = chrome.bounds

        // Snipaste: first / last tools extend the bar into the card’s rounded corners.
        if buttonRect.minX <= Self.edgeExtendSlop {
            width += x
            x = 0
        }
        if buttonRect.maxX >= bounds.width - Self.edgeExtendSlop {
            width = bounds.width - x
        }

        let target = CGRect(
            x: x,
            y: 0,
            width: max(width, 1),
            height: Self.accentHeight
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().frame = target
            }
        } else {
            accent.frame = target
        }
    }
}

// MARK: - Palette swatch (Snipaste-like hover grow)

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

/// Snipaste-like value slider (mosaic intensity / magnifier scale): blue filled track
/// to the left of the knob, gray remainder; circular knob is hollow until hover / drag.
final class MosaicIntensitySlider: NSView {
    var minValue: Double = 3
    var maxValue: Double = 24
    var doubleValue: Double = 10 {
        didSet {
            let clamped = min(max(doubleValue, minValue), maxValue)
            if clamped != doubleValue {
                doubleValue = clamped
                return
            }
            needsDisplay = true
        }
    }

    weak var target: AnyObject?
    var action: Selector?

    var isHovered = false
    var isDragging = false
    var trackingArea: NSTrackingArea?

    private static let accent = NSColor.systemBlue
    private static let trackGray = NSColor(calibratedWhite: 0.72, alpha: 1)
    private static let knobDiameter: CGFloat = 12
    private static let trackHeight: CGFloat = 3

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Toolbar is a nonactivating panel — must use `.activeAlways` (same as palette chips).
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        syncHoverFromMouseLocation()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        if !isDragging {
            setHovered(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        setHovered(true)
        updateValue(from: event, notify: true)
        // Keep receiving drag/up even if the pointer leaves the view.
        var keepGoing = true
        while keepGoing {
            guard let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
            switch next.type {
            case .leftMouseDragged:
                updateValue(from: next, notify: true)
            default:
                keepGoing = false
            }
        }
        isDragging = false
        syncHoverFromMouseLocation()
        needsDisplay = true
    }

    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        needsDisplay = true
    }

    func syncHoverFromMouseLocation() {
        guard let window else { return }
        let loc = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(loc))
    }

    func updateValue(from event: NSEvent, notify: Bool) {
        let x = convert(event.locationInWindow, from: nil).x
        let inset = Self.knobDiameter / 2
        let usable = max(bounds.width - Self.knobDiameter, 1)
        let t = min(max((x - inset) / usable, 0), 1)
        let next = minValue + t * (maxValue - minValue)
        guard abs(next - doubleValue) > 0.0001 else { return }
        doubleValue = next
        guard notify, let target, let action else { return }
        _ = target.perform(action, with: self)
    }

    var knobCenterX: CGFloat {
        let inset = Self.knobDiameter / 2
        let usable = max(bounds.width - Self.knobDiameter, 1)
        let t = (doubleValue - minValue) / max(maxValue - minValue, 0.0001)
        return inset + CGFloat(t) * usable
    }

    override func draw(_ dirtyRect: NSRect) {
        let midY = bounds.midY
        let inset = Self.knobDiameter / 2
        let trackY = midY - Self.trackHeight / 2
        let trackRect = CGRect(
            x: inset,
            y: trackY,
            width: max(bounds.width - Self.knobDiameter, 0),
            height: Self.trackHeight
        )
        let radius = Self.trackHeight / 2
        let cx = knobCenterX

        // Right (unfilled) track.
        let grayPath = NSBezierPath(roundedRect: trackRect, xRadius: radius, yRadius: radius)
        Self.trackGray.setFill()
        grayPath.fill()

        // Left (filled) track through the knob center.
        let filledWidth = max(cx - trackRect.minX, 0)
        if filledWidth > 0 {
            let filled = CGRect(
                x: trackRect.minX,
                y: trackRect.minY,
                width: filledWidth,
                height: trackRect.height
            )
            let bluePath = NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius)
            Self.accent.setFill()
            bluePath.fill()
        }

        // Circular knob: hollow by default, filled on hover / drag.
        let knobRect = CGRect(
            x: cx - Self.knobDiameter / 2,
            y: midY - Self.knobDiameter / 2,
            width: Self.knobDiameter,
            height: Self.knobDiameter
        )
        let knobPath = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.5, dy: 0.5))
        let fillKnob = isHovered || isDragging
        if fillKnob {
            Self.accent.setFill()
            knobPath.fill()
        } else {
            // Punch a hole so the track doesn't show through the hollow ring.
            NSColor.white.setFill()
            knobPath.fill()
            Self.accent.setStroke()
            knobPath.lineWidth = 1.5
            knobPath.stroke()
        }
    }
}

/// Solid dot whose diameter tracks magnifier zoom (1×…6×) — Snipaste-style scale preview.
final class MagnifierScalePreviewView: NSView {
    var scale: CGFloat = MagnifierStyle.defaultScale {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let s = MagnifierStyle.clampedScale(scale)
        let t = (s - MagnifierStyle.scaleRange.lowerBound)
            / (MagnifierStyle.scaleRange.upperBound - MagnifierStyle.scaleRange.lowerBound)
        let diameter = 4 + t * 10 // 4pt @ 1× → 14pt @ 6×
        let rect = CGRect(
            x: (bounds.width - diameter) / 2,
            y: (bounds.height - diameter) / 2,
            width: diameter,
            height: diameter
        )
        NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
        NSBezierPath(ovalIn: rect).fill()
    }
}

/// Intensity chip: soft circle (no rim); interior softens with blur radius.
final class MosaicIntensityPreviewView: NSView {
    var intensity: CGFloat = 10

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private static let sampleImage: CIImage = {
        let px = 64
        let size = CGSize(width: px, height: px)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: px,
            pixelsHigh: px,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 10, y: 10, width: 44, height: 44)).fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 22, y: 22, width: 20, height: 20)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let ns = NSImage(size: size)
        ns.addRepresentation(rep)
        return CIImage(data: ns.tiffRepresentation!) ?? CIImage.empty()
    }()

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let intensity = MosaicStyle.clampedIntensity(intensity)
        let radius = MosaicStyle.blurRadiusPoints(forIntensity: intensity)

        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(Self.sampleImage.clampedToExtent(), forKey: kCIInputImageKey)
        filter?.setValue(max(radius * 1.2, 0.35), forKey: kCIInputRadiusKey)

        let shapePath = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))

        NSGraphicsContext.current?.saveGraphicsState()
        shapePath.addClip()
        let extent = Self.sampleImage.extent
        if let blurred = filter?.outputImage?.cropped(to: extent),
           let cg = Self.ciContext.createCGImage(blurred, from: extent) {
            NSImage(cgImage: cg, size: bounds.size)
                .draw(in: bounds, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
            shapePath.fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
