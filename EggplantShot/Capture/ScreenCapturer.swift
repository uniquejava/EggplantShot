import AppKit
import CoreGraphics
import Foundation

enum ScreenCapturer {
    /// Capture a rectangular region in Cocoa global coordinates (points, bottom-left origin).
    /// `rect` is in screen points; the returned image is pixel-backed at display scale.
    static func capture(rectInScreenPoints rect: CGRect) -> NSImage? {
        guard rect.width >= 1, rect.height >= 1 else { return nil }

        // Convert Cocoa bottom-left points → Quartz top-left pixels for the primary display space.
        // Multi-display: map through the screen that contains the rect's center.
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        let scale = screen.backingScaleFactor
        let displayID = screen.displayID

        // Quartz display bounds origin is top-left of that display in global Quartz space.
        var quartzDisplayBounds = CGDisplayBounds(displayID)

        // Cocoa screen.frame uses global bottom-left origin (primary screen bottom-left = 0,0).
        // Convert selection from Cocoa → relative to this screen, then to pixels.
        let localCocoa = CGRect(
            x: rect.origin.x - screen.frame.origin.x,
            y: rect.origin.y - screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )

        // Flip Y: Cocoa y=0 is bottom of screen; Quartz y=0 is top of display image.
        let pixelRect = CGRect(
            x: (localCocoa.origin.x * scale).rounded(.towardZero),
            y: ((screen.frame.height - localCocoa.origin.y - localCocoa.height) * scale).rounded(.towardZero),
            width: (localCocoa.width * scale).rounded(.awayFromZero),
            height: (localCocoa.height * scale).rounded(.awayFromZero)
        ).integral

        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return nil }

        guard let full = CGDisplayCreateImage(displayID) else {
            // Fallback: composite window list for the global quartz rect.
            let globalQuartz = CGRect(
                x: quartzDisplayBounds.origin.x + pixelRect.origin.x,
                y: quartzDisplayBounds.origin.y + pixelRect.origin.y,
                width: pixelRect.width,
                height: pixelRect.height
            )
            guard let image = CGWindowListCreateImage(
                globalQuartz,
                .optionOnScreenBelowWindow,
                kCGNullWindowID,
                [.bestResolution, .nominalResolution]
            ) else {
                return nil
            }
            return nsImage(from: image, pointSize: rect.size)
        }

        guard let cropped = full.cropping(to: pixelRect) else { return nil }
        return nsImage(from: cropped, pointSize: rect.size)
    }

    private static func nsImage(from cgImage: CGImage, pointSize: CGSize) -> NSImage {
        let image = NSImage(cgImage: cgImage, size: pointSize)
        return image
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
}
