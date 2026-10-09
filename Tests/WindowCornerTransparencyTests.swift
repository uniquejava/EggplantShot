import AppKit

@main
struct WindowCornerTransparencyTests {
    @MainActor
    static func main() {
        do {
            try runChecks()
        } catch {
            print("FAIL:", error)
            exit(1)
        }
    }

    @MainActor
    static func runChecks() throws {
        let frozen = bitmap(width: 64, height: 48) { context in
            context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
        for radius in [CGFloat(4), 12] {
            let outline = bitmap(width: 64, height: 48) { context in
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.addPath(CGPath(
                    roundedRect: CGRect(x: 0, y: 0, width: 64, height: 48),
                    cornerWidth: radius, cornerHeight: radius, transform: nil
                ))
                context.fillPath()
            }
            let result = try require(WindowCornerTransparency.applyingOutline(outline, to: frozen))
            for (x, y) in [(0, 0), (63, 0), (0, 47), (63, 47)] {
                try expect(pixel(result, x, y)[3] == 0, "Round corner must be clear")
            }
            try expect(pixel(result, 32, 24) == pixel(frozen, 32, 24), "Freeze RGB must stay unchanged")
            try expect(result.width == 64 && result.height == 48, "Pixel dimensions must stay unchanged")
        }

        let opaque = try require(WindowCornerTransparency.applyingOutline(frozen, to: frozen))
        try expect(pixel(opaque, 0, 0) == pixel(frozen, 0, 0), "Square window must keep its corners")
        let wrongSize = bitmap(width: 8, height: 8) { _ in }
        try expect(WindowCornerTransparency.applyingOutline(wrongSize, to: frozen) == nil, "Reject misaligned outlines")

        // Asymmetric shape proves that the mask is neither mirrored nor replaced by a fixed radius.
        let asymmetric = bitmap(width: 64, height: 48) { context in
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            context.clear(CGRect(x: 0, y: 0, width: 8, height: 8))
            context.clear(CGRect(x: 30, y: 22, width: 4, height: 4))
            context.setBlendMode(.copy)
            context.setFillColor(CGColor(gray: 1, alpha: 0.5))
            context.fill(CGRect(x: 8, y: 0, width: 1, height: 8))
            context.fill(CGRect(x: 12, y: 12, width: 4, height: 4))
        }
        let cleared = try require(WindowCornerTransparency.applyingOutline(asymmetric, to: frozen))
        for (x, y) in [(0, 0), (63, 0), (0, 47), (63, 47)] {
            let expected = pixel(asymmetric, x, y)[3] == 0 ? UInt8(0) : UInt8(255)
            try expect(pixel(cleared, x, y)[3] == expected, "Match each corner's own outline")
        }
        try expect(pixel(cleared, 32, 24)[3] == 255, "Interior transparent hole must not cut the freeze")
        // Find the partially transparent contour in the bitmap's row order.
        var feathered = false
        for y in 0..<48 {
            if pixel(asymmetric, 8, y)[3] == 128 {
                try expect(pixel(cleared, 8, y)[3] == 128, "Keep antialiasing next to the clear corner")
                feathered = true
            }
        }
        try expect(feathered, "Fixture must include an antialiased edge")
        try expect(pixel(cleared, 13, 13)[3] == 255, "Interior translucency must not fade the freeze")

        let rep = NSBitmapImageRep(cgImage: cleared)
        rep.size = NSSize(width: 32, height: 24)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        let png = try require(ScreenshotImageEncoder.data(from: image, format: .png))
        let decoded = try require(NSBitmapImageRep(data: png))
        try expect(decoded.pixelsWide == 64 && decoded.pixelsHigh == 48, "PNG must retain Retina pixels")
        try expect(decoded.colorAt(x: 0, y: 47)!.alphaComponent == 0, "PNG must retain clear corner")

        let jpeg = try require(ScreenshotImageEncoder.data(from: image, format: .jpeg))
        let decodedJPEG = try require(NSBitmapImageRep(data: jpeg))
        let white = try require(decodedJPEG.colorAt(x: 0, y: 47)?.usingColorSpace(.deviceRGB))
        try expect(!decodedJPEG.hasAlpha && white.redComponent > 0.9 && white.greenComponent > 0.9,
                   "JPEG corner must be opaque white")
        try expect(decodedJPEG.pixelsWide == 64 && decodedJPEG.pixelsHigh == 48, "JPEG must retain Retina pixels")

        let mark = Annotation(
            rect: CGRect(x: 12, y: 8, width: 8, height: 8),
            style: AnnotationStyle(strokeWidth: 1, strokeColor: .blue, isFilled: true, lineStyle: .solid)
        )
        let baked = AnnotationCompositor.composite([mark], onto: image)
        let bakedPNG = try require(ScreenshotImageEncoder.data(from: baked, format: .png))
        let bakedRep = try require(NSBitmapImageRep(data: bakedPNG))
        try expect(bakedRep.pixelsWide == 64 && bakedRep.colorAt(x: 0, y: 47)!.alphaComponent == 0,
                   "Annotation bake must retain alpha and Retina pixels")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SnipHistoryStore(rootURL: root)
        store.append(SnipRecord(baseImage: image, selection: CGRect(origin: .zero, size: image.size),
                               document: AnnotationDocument(marks: [mark])))
        let restored = try require(SnipHistoryStore(rootURL: root).newest)
        let restoredPNG = try require(ScreenshotImageEncoder.data(from: restored.baseImage, format: .png))
        let restoredRep = try require(NSBitmapImageRep(data: restoredPNG))
        try expect(restoredRep.pixelsWide == 64 && restoredRep.colorAt(x: 0, y: 47)!.alphaComponent == 0,
                   "Disk history must retain alpha and Retina pixels")
        try expect(restored.document.marks.count == 1, "History annotations must remain editable")
        print("PASS: actual outlines, square corners, alignment, antialiasing, freeze pixels, PNG/JPEG, annotation bake, disk history")
    }

    static func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                    | CGBitmapInfo.byteOrder32Big.rawValue)!
        draw(context)
        return context.makeImage()!
    }

    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let bytes = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return Array(bytes[offset..<(offset + 4)])
    }

    static func require<T>(_ value: T?, line: Int = #line) throws -> T {
        guard let value else { throw CheckFailure(message: "Unexpected nil at line \(line)") }
        return value
    }

    static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure(message: message) }
    }

    struct CheckFailure: Error { let message: String }
}
