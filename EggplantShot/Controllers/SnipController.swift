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
    /// Editable snip history (memory + disk). Inspect `newest` / `records` after confirm.
    let historyStore = SnipHistoryStore()

    private var isSnipping = false

    init() {
        overlay.historyStore = historyStore
    }

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
            // Capture and copy: no refine / annotate — copy as soon as the region is locked.
            let outcome = await overlay.beginSelection(
                primaryAction: primary,
                skipsRefine: mode == .copy,
                pinFrames: pinBoard.visiblePinFrames()
            )
            switch outcome {
            case .cancelled:
                return
            case .ocr(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                copyTextToClipboard(text)
                FeedbackSound.playOCRSuccess()
            case .confirmed(let rect, let baseImage, let action, let document):
                // Bake for export only; archive keeps the unannotated base + document.
                let baked = AnnotationCompositor.composite(document.marks, onto: baseImage)
                historyStore.append(
                    SnipRecord(baseImage: baseImage, selection: rect, document: document)
                )
                switch action {
                case .pin:
                    pinBoard.pin(baked, near: rect)
                case .copy:
                    copyToClipboard(baked)
                case .save:
                    ImageFileSaver.saveInteractive(baked)
                }
            }
        }
    }

    func toggleHideShowImages() {
        pinBoard.toggleHideShow()
    }

    /// Snipaste-style Paste: clipboard → floating pin (image / color card / text / image file).
    func pasteFromClipboard() {
        guard !overlay.isActive else { return }
        guard let image = ClipboardPaster.imageFromPasteboard() else { return }
        if pinBoard.imagesHidden {
            pinBoard.toggleHideShow()
        }
        let mouse = NSEvent.mouseLocation
        let anchor = CGRect(x: mouse.x - 1, y: mouse.y - 1, width: 2, height: 2)
        pinBoard.pin(image, near: anchor)
    }

    private func copyToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    private func copyTextToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
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
