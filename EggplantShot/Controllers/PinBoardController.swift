import AppKit
import SwiftUI

struct PinItem: Identifiable, Equatable {
    let id: UUID
    let image: NSImage
    let createdAt: Date
    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "Image \(formatter.string(from: createdAt))"
    }
}

/// Manages floating pinned screenshot panels (Snipaste-style).
@MainActor
final class PinBoardController: ObservableObject {
    @Published private(set) var items: [PinItem] = []
    @Published private(set) var imagesHidden = false

    private var panels: [UUID: PinPanel] = [:]

    func pin(_ image: NSImage, near rect: CGRect) {
        let item = PinItem(id: UUID(), image: image, createdAt: Date())
        items.append(item)

        let size = image.size
        // Extra padding so the blue/gray ring + glow sit outside the bitmap.
        let pad = PinPanel.chromePadding
        var frame = CGRect(
            x: rect.midX - size.width / 2 - pad,
            y: rect.midY - size.height / 2 - pad,
            width: max(size.width, 1) + pad * 2,
            height: max(size.height, 1) + pad * 2
        )

        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main {
            frame.origin.x = min(max(frame.origin.x, screen.frame.minX), screen.frame.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, screen.frame.minY), screen.frame.maxY - frame.height)
        }

        let panel = PinPanel(itemID: item.id, image: image, frame: frame) { [weak self] id in
            self?.close(id)
        }
        panels[item.id] = panel
        // New pin means the user wants pins on screen again (incl. after ⇧F3 hide-all).
        revealAllIfHidden()
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        objectWillChange.send()
    }

    func close(_ id: UUID) {
        if let panel = panels.removeValue(forKey: id) {
            panel.orderOut(nil)
            panel.close()
        }
        items.removeAll { $0.id == id }
    }

    func closeAll() {
        for id in items.map(\.id) {
            close(id)
        }
    }

    func toggleHideShow() {
        imagesHidden.toggle()
        if imagesHidden {
            for panel in panels.values {
                panel.orderOut(nil)
            }
        } else {
            for panel in panels.values {
                panel.orderFrontRegardless()
            }
        }
    }

    func bringToFront(_ id: UUID) {
        revealAllIfHidden()
        panels[id]?.orderFrontRegardless()
    }

    /// Clears hide-all so every pin (and any newly created one) is visible again.
    private func revealAllIfHidden() {
        guard imagesHidden else { return }
        imagesHidden = false
        for panel in panels.values {
            panel.orderFrontRegardless()
        }
    }

    /// Pin image frames for hover hit-test during snip, front → back.
    /// Empty when pins are hidden via Hide all images.
    ///
    /// Do not use `NSApp.orderedWindows` — nonactivating pin panels are often omitted.
    func visiblePinFrames() -> [CGRect] {
        guard !imagesHidden, !panels.isEmpty else { return [] }
        let pad = PinPanel.chromePadding
        let byNumber = Dictionary(uniqueKeysWithValues: panels.map { ($0.value.windowNumber, $0.value) })

        // CGWindowList is front → back and includes our pin panels.
        let options: CGWindowListOption = [.optionOnScreenOnly]
        if let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            var frames: [CGRect] = []
            frames.reserveCapacity(byNumber.count)
            for info in infoList {
                guard let number = info[kCGWindowNumber as String] as? Int,
                      let panel = byNumber[number],
                      panel.isVisible
                else { continue }
                // Image content only (skip soft glow padding) so click-lock matches the bitmap.
                frames.append(panel.frame.insetBy(dx: pad, dy: pad))
            }
            if !frames.isEmpty { return frames }
        }

        // Fallback: newest pin first.
        return items.reversed().compactMap { item in
            guard let panel = panels[item.id], panel.isVisible else { return nil }
            return panel.frame.insetBy(dx: pad, dy: pad)
        }
    }
}
