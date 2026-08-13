import AppKit
import CoreGraphics
import Darwin
import Foundation

enum ScreenCapturer {
    /// Full-display snapshot in pixels (for freeze overlay). Call before showing overlay windows.
    static func captureDisplay(_ screen: NSScreen) -> CGImage? {
        LegacyCG.displayImage(screen.displayID)
    }

    /// Crop a frozen display image using a Cocoa global rect (points, bottom-left origin).
    static func crop(
        _ full: CGImage,
        rectInScreenPoints rect: CGRect,
        on screen: NSScreen
    ) -> NSImage? {
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        guard let pixelRect = pixelRect(for: rect, on: screen) else { return nil }
        guard let cropped = full.cropping(to: pixelRect) else { return nil }
        return nsImage(from: cropped, pointSize: rect.size)
    }

    /// Capture a rectangular region in Cocoa global coordinates (points, bottom-left origin).
    /// `rect` is in screen points; the returned image is pixel-backed at display scale.
    static func capture(rectInScreenPoints rect: CGRect) -> NSImage? {
        guard rect.width >= 1, rect.height >= 1 else { return nil }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        if let full = captureDisplay(screen) {
            return crop(full, rectInScreenPoints: rect, on: screen)
        }

        // Fallback: composite window list for the global quartz rect.
        guard let pixelRect = pixelRect(for: rect, on: screen) else { return nil }
        let quartzDisplayBounds = CGDisplayBounds(screen.displayID)
        let globalQuartz = CGRect(
            x: quartzDisplayBounds.origin.x + pixelRect.origin.x,
            y: quartzDisplayBounds.origin.y + pixelRect.origin.y,
            width: pixelRect.width,
            height: pixelRect.height
        )
        guard let image = LegacyCG.windowListImage(
            globalQuartz,
            .optionOnScreenBelowWindow,
            kCGNullWindowID,
            [.bestResolution, .nominalResolution]
        ) else {
            return nil
        }
        return nsImage(from: image, pointSize: rect.size)
    }

    /// Cocoa bottom-left points → pixel rect in the display image (top-left origin).
    private static func pixelRect(for rect: CGRect, on screen: NSScreen) -> CGRect? {
        let scale = screen.backingScaleFactor
        let localCocoa = CGRect(
            x: rect.origin.x - screen.frame.origin.x,
            y: rect.origin.y - screen.frame.origin.y,
            width: rect.width,
            height: rect.height
        )
        let pixel = CGRect(
            x: (localCocoa.origin.x * scale).rounded(.towardZero),
            y: ((screen.frame.height - localCocoa.origin.y - localCocoa.height) * scale).rounded(.towardZero),
            width: (localCocoa.width * scale).rounded(.awayFromZero),
            height: (localCocoa.height * scale).rounded(.awayFromZero)
        ).integral
        guard pixel.width >= 1, pixel.height >= 1 else { return nil }
        return pixel
    }

    private static func nsImage(from cgImage: CGImage, pointSize: CGSize) -> NSImage {
        NSImage(cgImage: cgImage, size: pointSize)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}

// MARK: - Legacy CG capture (symbols still present; SDK marks them unavailable at macOS 15+)

/// `CGDisplayCreateImage` / `CGWindowListCreateImage` were obsoleted in the macOS 15 SDK
/// (unavailable when deployment target ≥ 15). Resolve them at runtime until ScreenCaptureKit.
private enum LegacyCG {
    private static let coreGraphics = dlopen(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        RTLD_LAZY
    )

    private static let displayImageFn: (@convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?)? = {
        guard let handle = coreGraphics, let sym = dlsym(handle, "CGDisplayCreateImage") else { return nil }
        return unsafeBitCast(sym, to: (@convention(c) (CGDirectDisplayID) -> Unmanaged<CGImage>?).self)
    }()

    private static let windowListImageFn: (
        @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
    )? = {
        guard let handle = coreGraphics, let sym = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(
            sym,
            to: (@convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?).self
        )
    }()

    static func displayImage(_ displayID: CGDirectDisplayID) -> CGImage? {
        displayImageFn?(displayID)?.takeRetainedValue()
    }

    static func windowListImage(
        _ bounds: CGRect,
        _ listOption: CGWindowListOption,
        _ windowID: CGWindowID,
        _ imageOption: CGWindowImageOption
    ) -> CGImage? {
        windowListImageFn?(bounds, listOption, windowID, imageOption)?.takeRetainedValue()
    }
}
