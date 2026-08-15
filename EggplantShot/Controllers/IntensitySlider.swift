import AppKit
import CoreImage

/// Snipaste-like value slider (mosaic intensity / magnifier scale): blue filled track
/// to the left of the knob, gray remainder; knob is hollow until hover / drag.
final class MosaicIntensitySlider: NSView {
    /// Knob shape doubles as a mode readout: mosaic squares it in Pixelate mode, so the thing under
    /// your cursor mid-drag says which curve the number is feeding. Circle everywhere else.
    var knobIsSquare = false {
        didSet {
            guard knobIsSquare != oldValue else { return }
            needsDisplay = true
        }
    }

    var minValue: Double = 3
    var maxValue: Double = 24
    /// Snap increment measured from `minValue`; 0 = continuous (magnifier scale). Mosaic sets it so
    /// every drag lands on a value the label can show exactly.
    var step: Double = 0
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
    /// Called once when a drag starts / ends, around the run of `action` ticks — lets the owner
    /// coalesce the whole drag into a single undo step instead of one per tick.
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?

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
        // Before the first tick: the initial click already moves the knob.
        onDragBegan?()
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
        onDragEnded?()
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
        var next = minValue + t * (maxValue - minValue)
        if step > 0 {
            next = min(minValue + ((next - minValue) / step).rounded() * step, maxValue)
        }
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

        // Knob: hollow by default, filled on hover / drag; circle for Blur, square for Pixelate.
        let knobRect = CGRect(
            x: cx - Self.knobDiameter / 2,
            y: midY - Self.knobDiameter / 2,
            width: Self.knobDiameter,
            height: Self.knobDiameter
        ).insetBy(dx: 0.5, dy: 0.5)
        let knobPath = knobIsSquare
            ? NSBezierPath(roundedRect: knobRect, xRadius: 2, yRadius: 2)
            : NSBezierPath(ovalIn: knobRect)
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

/// Intensity chip: soft circle (no rim); interior softens with blur radius, or breaks into
/// blocks when the Pixelate effect is armed — so the chip says what the slider is driving.
///
/// Also **the effect switch** (Snipaste puts a toggle in this slot): clicking it flips
/// blur ⇄ pixelate. An `NSButton` rather than a plain view with a `mouseDown`, so it inherits the
/// row's existing machinery — `HoverChromeCard` walks up to the nearest button to slide the accent
/// underline and to show the custom tooltip, which is what makes a control that looks like a preview
/// still read as clickable. Drawing is fully overridden, so no cell chrome appears under it.
final class MosaicIntensityPreviewView: NSButton {
    var blurSigma: CGFloat = MosaicStyle.defaultBlurSigma
    var blockSize: CGFloat = MosaicStyle.defaultBlockSize
    var effect: MosaicEffect = .blur

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        isBordered = false
        bezelStyle = .inline
        imagePosition = .imageOnly
        setButtonType(.momentaryChange)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
        // A thin dark annulus, not a fat disc: the chip should read as a slim ring (Snipaste's
        // toggle glyph) rather than a blob. 8 of 64 px band ≈ 2 pt once drawn at `displayDiameter`.
        NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 9, y: 9, width: 46, height: 46)).fill()
        NSColor(calibratedWhite: 0.75, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: 17, y: 17, width: 30, height: 30)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let ns = NSImage(size: size)
        ns.addRepresentation(rep)
        return CIImage(data: ns.tiffRepresentation!) ?? CIImage.empty()
    }()

    override var isOpaque: Bool { false }

    /// Fills the 24 pt slot, matching the icon buttons beside it. Only the *band* was thinned — the
    /// glyph itself stayed this size because 17 pt read as too small next to them.
    private static let displayDiameter: CGFloat = 23

    override func draw(_ dirtyRect: NSRect) {
        // A relative indicator, not a 1:1 preview — and the two effects need *opposite* corrections.
        // Blur is exaggerated 1.6× because a 3 pt sigma shrinks to well under a point once the 64 px
        // sample is drawn at 23 pt. Pixelate is scaled *down*: blocks-across is `64 / block`, so it
        // depends on the sample rather than the drawn size, and at 1.6 (or even the original 1.2) the
        // top of the range collapsed to a single flat square. 0.7 keeps ~6 blocks at maximum, which
        // still reads as a lattice.
        let filter: CIFilter?
        switch effect {
        case .blur:
            filter = CIFilter(name: "CIGaussianBlur")
            filter?.setValue(Self.sampleImage.clampedToExtent(), forKey: kCIInputImageKey)
            filter?.setValue(
                max(MosaicStyle.clampedBlurSigma(blurSigma) * 1.6, 0.35), forKey: kCIInputRadiusKey)
        case .pixelate:
            let block = max(MosaicStyle.clampedBlockSize(blockSize) * 0.7, 1)
            let pixellate = CIFilter(name: "CIPixellate")
            pixellate?.setValue(Self.sampleImage.clampedToExtent(), forKey: kCIInputImageKey)
            pixellate?.setValue(block, forKey: kCIInputScaleKey)
            // Grid centred on the 64pt sample so the chip stays symmetric.
            pixellate?.setValue(CIVector(x: 32, y: 32), forKey: kCIInputCenterKey)
            filter = pixellate
        }

        let glyphRect = CGRect(
            x: bounds.midX - Self.displayDiameter / 2,
            y: bounds.midY - Self.displayDiameter / 2,
            width: Self.displayDiameter,
            height: Self.displayDiameter
        )
        let shapePath = NSBezierPath(ovalIn: glyphRect)

        NSGraphicsContext.current?.saveGraphicsState()
        shapePath.addClip()
        let extent = Self.sampleImage.extent
        if let blurred = filter?.outputImage?.cropped(to: extent),
           let cg = Self.ciContext.createCGImage(blurred, from: extent) {
            NSImage(cgImage: cg, size: glyphRect.size)
                .draw(in: glyphRect, from: .zero, operation: .copy, fraction: 1)
        } else {
            NSColor(calibratedWhite: 0.85, alpha: 1).setFill()
            shapePath.fill()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}
