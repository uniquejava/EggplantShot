import AppKit
import CoreGraphics

// Offscreen bitmap the marks layer is drawn into.

/// Owns its bitmap so tools can read back the pixels drawn **so far**.
///
/// `NSImage(size:flipped:)` offers no readback, which forced mosaic / magnifier to re-derive
/// everything underneath them from vectors on every redraw. Owning the buffer means a mosaic
/// can copy the hull it is about to blur straight out of the layer: correct for a mosaic over
/// an earlier mosaic (that one's blurred pixels are already in the buffer), and O(hull) instead
/// of O(prior marks) — no recursion, so no combinatorial rebuild.
///
/// Drawing happens in **points** (the CTM is pre-scaled), origin bottom-left, matching the
/// overlay's `isFlipped == false`. `snapshotCrop` converts points → pixels itself.
final class MarksCanvas {
    let context: CGContext
    /// Layer size in points.
    let size: CGSize
    let scale: CGFloat

    private let pixelWidth: Int
    private let pixelHeight: Int
    private let colorSpace: CGColorSpace

    private static let bitmapInfo =
        CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    /// `colorSpace` should be the space the layer will be drawn into (screen for the overlay,
    /// the base image for a bake). The old block-backed `NSImage` inherited the destination's
    /// space; hardcoding one here would round-trip P3 marks through it and dull them.
    init?(size: CGSize, scale: CGFloat, colorSpace: CGColorSpace? = nil) {
        guard size.width > 0, size.height > 0, scale > 0 else { return nil }
        let w = Int((size.width * scale).rounded())
        let h = Int((size.height * scale).rounded())
        guard w > 0, h > 0 else { return nil }
        let space = colorSpace
            ?? CGColorSpace(name: CGColorSpace.sRGB)
            ?? CGColorSpaceCreateDeviceRGB()
        // `data: nil` → CoreGraphics owns the buffer, so there is nothing to free by hand.
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: Self.bitmapInfo
        ) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        context = ctx
        pixelWidth = w
        pixelHeight = h
        self.colorSpace = space
        self.size = size
        self.scale = scale
    }

    /// Runs `body` with this canvas installed as `NSGraphicsContext.current`, so existing
    /// AppKit drawing (`NSBezierPath`, `NSImage.draw`) works unchanged.
    func draw(_ body: () -> Void) {
        let ns = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        body()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Marks drawn so far inside `rect` (points, canvas space), as an upright image.
    ///
    /// Copies only the hull's rows out of the backing store — a full-layer `makeImage()` per
    /// mosaic would memcpy the whole screen instead.
    func snapshotCrop(_ rect: CGRect) -> CGImage? {
        guard let data = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight))
        let pixels = CGRect(
            x: rect.minX * scale,
            y: rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral.intersection(bounds)
        guard pixels.width >= 1, pixels.height >= 1 else { return nil }

        let x = Int(pixels.minX)
        let w = Int(pixels.width)
        let h = Int(pixels.height)
        // Bitmap memory row 0 is the **top** scanline; canvas y is bottom-up.
        let top = pixelHeight - Int(pixels.maxY)
        guard top >= 0, top + h <= pixelHeight, x + w <= pixelWidth else { return nil }

        let outBytesPerRow = w * 4
        guard let out = malloc(outBytesPerRow * h) else { return nil }
        for row in 0..<h {
            memcpy(
                out.advanced(by: row * outBytesPerRow),
                data.advanced(by: (top + row) * bytesPerRow + x * 4),
                outBytesPerRow
            )
        }
        guard let provider = CGDataProvider(
            dataInfo: out,
            data: out,
            size: outBytesPerRow * h,
            releaseData: { info, _, _ in free(info) }
        ) else {
            free(out)
            return nil
        }
        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: outBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Wraps this canvas's buffer as an image **without copying it** — a full-layer
    /// `context.makeImage()` costs a screen-sized memcpy on every render.
    ///
    /// The returned image shares the pixels, so the canvas must not be drawn into again. The
    /// provider retains the canvas, keeping CoreGraphics' buffer alive as long as the image.
    func finishedImage() -> NSImage? {
        guard let data = context.data else { return nil }
        let byteCount = context.bytesPerRow * pixelHeight
        let retained = Unmanaged.passRetained(self).toOpaque()
        guard let provider = CGDataProvider(
            dataInfo: retained,
            data: data,
            size: byteCount,
            releaseData: { info, _, _ in
                if let info { Unmanaged<MarksCanvas>.fromOpaque(info).release() }
            }
        ) else {
            Unmanaged<MarksCanvas>.fromOpaque(retained).release()
            return nil
        }
        guard let cg = CGImage(
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: context.bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: Self.bitmapInfo),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }
        return NSImage(cgImage: cg, size: size)
    }
}
