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
        var frame = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: max(size.width, 1),
            height: max(size.height, 1)
        )

        // Keep on-screen if possible.
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(rect) }) ?? NSScreen.main {
            frame.origin.x = min(max(frame.origin.x, screen.frame.minX), screen.frame.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, screen.frame.minY), screen.frame.maxY - frame.height)
        }

        let panel = PinPanel(itemID: item.id, image: image, frame: frame) { [weak self] id in
            self?.close(id)
        }
        panels[item.id] = panel
        if !imagesHidden {
            panel.orderFrontRegardless()
        }
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
        panels[id]?.orderFrontRegardless()
        imagesHidden = false
    }
}

private final class PinPanel: NSPanel {
    private let itemID: UUID
    private let onClose: (UUID) -> Void
    private var dragOffset: CGPoint = .zero

    init(itemID: UUID, image: NSImage, frame: CGRect, onClose: @escaping (UUID) -> Void) {
        self.itemID = itemID
        self.onClose = onClose

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        isOpaque = true
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.wantsLayer = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.separatorColor.cgColor

        let container = PinContentView(frame: CGRect(origin: .zero, size: frame.size))
        container.addSubview(imageView)
        imageView.autoresizingMask = [.width, .height]
        container.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.onClose(self.itemID)
        }
        container.onEscape = { [weak self] in
            guard let self else { return }
            self.onClose(self.itemID)
        }
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PinContentView: NSView {
    var onDoubleClick: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        // Allow window dragging via isMovableByWindowBackground.
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
