import AppKit
import CoreImage

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
