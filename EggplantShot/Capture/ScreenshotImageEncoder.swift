import AppKit

/// Pixel-preserving encoding shared by screenshot and pin saves.
enum ScreenshotImageEncoder {
    static func data(from image: NSImage, format: NSBitmapImageRep.FileType) -> Data? {
        guard let tiff = image.tiffRepresentation,
              var rep = NSBitmapImageRep(data: tiff)
        else { return nil }

        if format == .jpeg, rep.hasAlpha {
            // JPEG has no alpha: use a predictable white background instead of black corners.
            guard let opaque = opaqueBitmap(rep) else { return nil }
            rep = opaque
        }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = format == .jpeg
            ? [.compressionFactor: 0.9] : [:]
        return rep.representation(using: format, properties: properties)
    }

    private static func opaqueBitmap(_ source: NSBitmapImageRep) -> NSBitmapImageRep? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: source.pixelsWide, pixelsHigh: source.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = source.size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let bounds = CGRect(origin: .zero, size: source.size)
        NSColor.white.setFill()
        bounds.fill()
        source.draw(in: bounds)
        return rep
    }
}
