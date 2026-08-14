import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCapturer {
    /// Full-display snapshot in pixels (for freeze overlay). Call before showing overlay windows.
    static func captureDisplay(_ screen: NSScreen) async -> CGImage? {
        do {
            let content = try await SCShareableContent.current
            return try await captureDisplay(screen, content: content)
        } catch {
            return nil
        }
    }

    /// Freeze every connected display. Fetches shareable content once, then captures in parallel.
    /// Includes this app’s pin panels and menu-bar icon so F1 can re-snip them (Snipaste parity).
    static func captureAllDisplays() async -> [(screen: NSScreen, image: CGImage)] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            return []
        }

        return await withTaskGroup(of: (Int, CGImage)?.self) { group in
            for (index, screen) in screens.enumerated() {
                group.addTask {
                    guard let image = try? await captureDisplay(screen, content: content) else {
                        return nil
                    }
                    return (index, image)
                }
            }
            var byIndex: [Int: CGImage] = [:]
            for await item in group {
                if let (index, image) = item {
                    byIndex[index] = image
                }
            }
            return screens.enumerated().compactMap { index, screen in
                guard let image = byIndex[index] else { return nil }
                return (screen, image)
            }
        }
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

    /// Average luminance 0…1 around a Cocoa global point (for contrast chrome).
    static func averageLuminance(
        in full: CGImage,
        aroundPointInScreenPoints point: CGPoint,
        on screen: NSScreen
    ) -> CGFloat? {
        let sample = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
        guard let pixel = pixelRect(for: sample, on: screen),
              let cropped = full.cropping(to: pixel)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cropped)
        return ContrastChrome.averageLuminance(of: rep)
    }

    /// Capture a rectangular region in Cocoa global coordinates (points, bottom-left origin).
    /// `rect` is in screen points; the returned image is pixel-backed at display scale.
    static func capture(rectInScreenPoints rect: CGRect) async -> NSImage? {
        guard rect.width >= 1, rect.height >= 1 else { return nil }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return nil }

        guard let full = await captureDisplay(screen) else { return nil }
        return crop(full, rectInScreenPoints: rect, on: screen)
    }

    // MARK: - ScreenCaptureKit

    private static func captureDisplay(
        _ screen: NSScreen,
        content: SCShareableContent
    ) async throws -> CGImage {
        let displayID = screen.displayID
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound(displayID)
        }

        // Do not exclude our app: pins + menu-bar icon must stay in the freeze so the user
        // can re-snip them. Overlays are shown only after this capture returns.
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = Int((CGFloat(display.width) * scale).rounded(.toNearestOrAwayFromZero))
        config.height = Int((CGFloat(display.height) * scale).rounded(.toNearestOrAwayFromZero))
        config.showsCursor = false
        config.scalesToFit = false

        return try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
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

    private enum CaptureError: Error {
        case displayNotFound(CGDirectDisplayID)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
