import AppKit
import ScreenCaptureKit

/// Removes only the background connected to a window's four corners. Window pixels, including
/// vibrancy, occlusion and the cursor, continue to come from the original display freeze.
enum WindowCornerTransparency {
    @MainActor
    static func apply(to image: NSImage, target: WindowHitTester.Target) async -> NSImage {
        guard let id = target.windowID, let frame = target.quartzFrame,
              let frozen = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              WindowHitTester.isCurrent(target), !Task.isCancelled
        else { return image }

        do {
            let content = try await SCShareableContent.current
            guard let window = content.windows.first(where: { $0.windowID == id }),
                  window.frame == frame, !Task.isCancelled
            else { return image }

            let config = SCStreamConfiguration()
            config.width = frozen.width
            config.height = frozen.height
            config.showsCursor = false
            config.scalesToFit = true
            config.ignoreShadowsSingleWindow = true
            config.shouldBeOpaque = false
            let background = CGColor(gray: 0, alpha: 0)
            // ScreenCaptureKit's backgroundColor property is unowned(unsafe).
            defer { withExtendedLifetime(background) {} }
            config.backgroundColor = background
            let outline = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: config
            )
            guard !Task.isCancelled, WindowHitTester.isCurrent(target),
                  let result = applyingOutline(outline, to: frozen)
            else { return image }
            let rep = NSBitmapImageRep(cgImage: result)
            rep.size = image.size
            let transparent = NSImage(size: image.size)
            transparent.addRepresentation(rep)
            return transparent
        } catch {
            // A disappearing / unshareable window must never prevent a normal screenshot.
            return image
        }
    }

    static func applyingOutline(_ outline: CGImage, to frozen: CGImage) -> CGImage? {
        let width = frozen.width
        let height = frozen.height
        guard width >= 2, height >= 2,
              outline.width == width, outline.height == height,
              let shape = bitmapContext(width: width, height: height, colorSpace: CGColorSpaceCreateDeviceRGB()),
              let output = bitmapContext(
                width: width, height: height,
                colorSpace: frozen.colorSpace ?? CGColorSpaceCreateDeviceRGB()
              ),
              let shapeData = shape.data?.assumingMemoryBound(to: UInt8.self),
              let outputData = output.data?.assumingMemoryBound(to: UInt8.self)
        else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        shape.draw(outline, in: bounds)
        output.draw(frozen, in: bounds)

        // Flood fully transparent pixels from each corner, stopping at the quarter boundaries.
        // Interior translucency / transparent holes are not a request to fade the frozen bitmap.
        // No radius is assumed: square windows have no transparent corner to flood.
        var changed = false
        for (right, bottom) in [(false, false), (true, false), (false, true), (true, true)] {
            let xs = right ? (width / 2)..<width : 0..<(width / 2)
            let ys = bottom ? (height / 2)..<height : 0..<(height / 2)
            let startX = right ? width - 1 : 0
            let startY = bottom ? height - 1 : 0
            func alpha(_ x: Int, _ y: Int) -> UInt8 {
                shapeData[y * shape.bytesPerRow + x * 4 + 3]
            }
            guard alpha(startX, startY) == 0 else { continue }

            var queue = [(startX, startY)]
            var visited: Set<Int> = [startY * width + startX]
            var index = 0
            while index < queue.count {
                let (x, y) = queue[index]
                index += 1
                let opacity = Int(alpha(x, y))
                let offset = y * output.bytesPerRow + x * 4
                for component in 0..<4 {
                    outputData[offset + component] = UInt8(
                        (Int(outputData[offset + component]) * opacity + 127) / 255
                    )
                }
                changed = true
                // Include the antialiased boundary next to the clear region, without traversing
                // partially transparent title bars or other window content.
                guard opacity == 0 else { continue }
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                    guard xs.contains(nx), ys.contains(ny), alpha(nx, ny) < 255,
                          visited.insert(ny * width + nx).inserted
                    else { continue }
                    queue.append((nx, ny))
                }
            }
        }
        return changed ? output.makeImage() : frozen
    }

    private static func bitmapContext(width: Int, height: Int, colorSpace: CGColorSpace) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
    }
}
