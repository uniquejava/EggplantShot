import AppKit
import Foundation

enum SnipMode {
    case pin
    case copy
}

/// Coordinates selection → capture → pin / clipboard / save.
@MainActor
final class SnipController {
    let overlay = SelectionOverlayController()
    let pinBoard = PinBoardController()

    private var isSnipping = false

    func snip(mode: SnipMode) {
        guard !isSnipping, !overlay.isActive else { return }
        isSnipping = true

        Task { @MainActor in
            defer { isSnipping = false }

            guard ScreenPermissions.requestScreenAccess() else {
                promptScreenPermission()
                return
            }

            let primary: SelectionOverlayController.ConfirmAction = (mode == .pin) ? .pin : .copy
            let outcome = await overlay.beginSelection(primaryAction: primary)
            switch outcome {
            case .cancelled:
                return
            case .confirmed(let rect, let action):
                // Tiny delay so overlay panels are fully torn down before capture.
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard let image = ScreenCapturer.capture(rectInScreenPoints: rect) else {
                    NSLog("EggplantShot: capture failed for rect \(rect)")
                    return
                }
                switch action {
                case .pin:
                    pinBoard.pin(image, near: rect)
                case .copy:
                    copyToClipboard(image)
                case .save:
                    ImageFileSaver.saveInteractive(image)
                }
            }
        }
    }

    func toggleHideShowImages() {
        pinBoard.toggleHideShow()
    }

    private func copyToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    private func promptScreenPermission() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Access Needed"
        alert.informativeText = "EggplantShot needs Screen Recording permission to capture your screen."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenPermissions.openScreenCaptureSettings()
        }
    }
}
