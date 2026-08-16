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

    /// Its own controller so annotating a pin never disturbs a capture's state (or its undo stack).
    /// Deliberately without a `historyStore`, which is what leaves `,` / `.` inert while pin-editing.
    private let pinEditOverlay = SelectionOverlayController()

    private var isSnipping = false

    init() {
        overlay.historyStore = historyStore
        pinBoard.onShowToolbarRequested = { [weak self] id in
            self?.beginPinEdit(id)
        }
        // A pin being closed under an open session: drop the session, not just its lid.
        pinBoard.onWillClosePin = { [weak self] id in
            self?.endPinEdit(on: id, keepingMarks: false)
        }
    }

    func toggleHideShowImages() {
        // Hiding the pin being annotated would leave a toolbar floating over nothing; finish the
        // session first, keeping the work.
        endPinEdit(on: nil, keepingMarks: true)
        pinBoard.toggleHideShow()
    }

    /// Resolve an open pin-edit session before something else disturbs its pin. `id` limits this to
    /// a session on that specific pin; `nil` means any session.
    private func endPinEdit(on id: UUID?, keepingMarks: Bool) {
        guard pinEditOverlay.isActive else { return }
        if let id, pinEditOverlay.pinEdit?.itemID != id { return }
        if keepingMarks {
            pinEditOverlay.applyPinEdit()
        } else {
            pinEditOverlay.discardPinEdit()
        }
    }

    /// Right-click a pin → Show toolbar: annotate that pin where it sits.
    func beginPinEdit(_ id: UUID) {
        guard !overlay.isActive, !pinEditOverlay.isActive else { return }
        guard let target = pinBoard.annotationTarget(id) else { return }

        Task { @MainActor in
            let outcome = await pinEditOverlay.beginPinEdit(
                itemID: id,
                image: target.image,
                imageRect: target.rect
            )
            switch outcome {
            case .discarded:
                break
            case .applied(let document):
                // Snipaste parity: the marks become part of the pin's bitmap.
                pinBoard.replaceImage(
                    id,
                    with: AnnotationCompositor.composite(document.marks, onto: target.image)
                )
            case .copied(let baked):
                copyToClipboard(baked)
                pinBoard.close(id)
            case .saved(let baked):
                // Close first: the save panel must not open behind the pin (or the lid we just tore
                // down), which is the same reason `ImageFileSaver` lowers pin levels.
                pinBoard.close(id)
                ImageFileSaver.saveInteractive(baked)
            case .ocr(let text):
                pinBoard.close(id)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                copyTextToClipboard(text)
                FeedbackSound.playOCRSuccess()
            }
        }
    }

    func snip(mode: SnipMode) {
        guard !isSnipping, !overlay.isActive, !pinEditOverlay.isActive else { return }
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

    /// Snipaste-style Paste: clipboard → floating pin (image / color card / text / image file).
    func pasteFromClipboard() {
        guard !overlay.isActive, !pinEditOverlay.isActive else { return }
        guard let paste = ClipboardPaster.imageFromPasteboard() else { return }
        let mouse = NSEvent.mouseLocation
        let anchor = CGRect(x: mouse.x - 1, y: mouse.y - 1, width: 2, height: 2)
        pinBoard.pin(paste.image, near: anchor, sourceText: paste.sourceText)
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
        alert.messageText = L10n.tr("Screen Recording Access Needed")
        alert.informativeText = L10n.tr("screen_alert_body_short")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.tr("Open System Settings"))
        alert.addButton(withTitle: L10n.tr("Later"))
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenPermissions.openScreenCaptureSettings()
        }
    }
}
