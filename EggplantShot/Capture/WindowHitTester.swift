import AppKit
import CoreGraphics
import Foundation

/// Front-to-back hit testing of on-screen app windows (Snipaste-style pick under cursor).
struct WindowHitTester {
    /// Window frames in Cocoa global coordinates (points, bottom-left origin), front → back.
    private let frames: [CGRect]

    /// Snapshot visible windows, excluding our process, Dock, menu bar, and desktop chrome.
    static func snapshot(excludingPID pid: pid_t = ProcessInfo.processInfo.processIdentifier) -> WindowHitTester {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return WindowHitTester(frames: [])
        }

        let dockLevel = CGWindowLevelForKey(.dockWindow)
        var frames: [CGRect] = []
        frames.reserveCapacity(infoList.count)

        for info in infoList {
            if let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid {
                continue
            }
            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            // Keep normal / floating / utility / modal; skip Dock, menu bar, status, screensaver.
            guard layer < Int(dockLevel) else { continue }

            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let quartz = cgRect(fromWindowBounds: boundsDict)
            else { continue }
            guard quartz.width >= 2, quartz.height >= 2 else { continue }

            let cocoa = quartzRectToCocoa(quartz)
            frames.append(cocoa)
        }

        return WindowHitTester(frames: frames)
    }

    func windowFrame(at point: CGPoint) -> CGRect? {
        frames.first { $0.contains(point) }
    }

    private static func cgRect(fromWindowBounds dict: [String: Any]) -> CGRect? {
        func num(_ key: String) -> CGFloat? {
            if let n = dict[key] as? CGFloat { return n }
            if let n = dict[key] as? NSNumber { return CGFloat(truncating: n) }
            return nil
        }
        guard let x = num("X"), let y = num("Y"), let w = num("Width"), let h = num("Height") else {
            return nil
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Quartz global (top-left of main display) → Cocoa global (bottom-left of main display).
    private static func quartzRectToCocoa(_ quartz: CGRect) -> CGRect {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let mainHeight = primary?.frame.height ?? CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(
            x: quartz.origin.x,
            y: mainHeight - quartz.origin.y - quartz.height,
            width: quartz.width,
            height: quartz.height
        )
    }
}
