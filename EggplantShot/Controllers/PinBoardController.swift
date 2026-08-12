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
        if !imagesHidden {
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)
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
    /// Room outside the bitmap for the soft outer glow (must be ≥ blur radius).
    static let chromePadding: CGFloat = 10

    private let itemID: UUID
    private let onClose: (UUID) -> Void
    private let chromeView: PinChromeView
    private var keyObservers: [NSObjectProtocol] = []

    init(itemID: UUID, image: NSImage, frame: CGRect, onClose: @escaping (UUID) -> Void) {
        self.itemID = itemID
        self.onClose = onClose

        let pad = Self.chromePadding
        let imageSize = CGSize(
            width: max(frame.width - pad * 2, 1),
            height: max(frame.height - pad * 2, 1)
        )
        let chrome = PinChromeView(frame: CGRect(origin: .zero, size: frame.size), image: image, imageSize: imageSize)
        self.chromeView = chrome

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Above normal / floating app windows so pins are not buried; still below
        // the snip overlay (.screenSaver) used while selecting.
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        chrome.onDoubleClick = { [weak self] in
            guard let self else { return }
            self.onClose(self.itemID)
        }
        chrome.onEscape = { [weak self] in
            guard let self else { return }
            self.onClose(self.itemID)
        }
        chrome.onMouseDown = { [weak self] in
            self?.makeKeyAndOrderFront(nil)
        }
        contentView = chrome

        let center = NotificationCenter.default
        keyObservers.append(center.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.chromeView.setActive(true)
        })
        keyObservers.append(center.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.chromeView.setActive(false)
        })

        chromeView.setActive(true)
    }

    deinit {
        for obs in keyObservers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Image + Snipaste-style outer glow (CSS `box-shadow: 0 0 blur color` — no hard border).
private final class PinChromeView: NSView {
    var onDoubleClick: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMouseDown: (() -> Void)?

    private let imageView: NSImageView

    /// ≈ CSS `box-shadow: 0 0 12px rgb(51,140,255)`
    private let activeGlow = NSColor(calibratedRed: 0.20, green: 0.55, blue: 1.0, alpha: 1)
    private let inactiveGlow = NSColor(calibratedWhite: 0.65, alpha: 1)

    init(frame: CGRect, image: NSImage, imageSize: CGSize) {
        let pad = PinPanel.chromePadding
        imageView = NSImageView(frame: CGRect(x: pad, y: pad, width: imageSize.width, height: imageSize.height))
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = false

        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(imageView)
        imageView.autoresizingMask = [.width, .height]
        applyGlow(active: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func layout() {
        super.layout()
        let pad = PinPanel.chromePadding
        imageView.frame = bounds.insetBy(dx: pad, dy: pad)
        // shadowPath = exact image rect → glow hugs the bitmap edge (like box-shadow on the img).
        if let layer = imageView.layer {
            layer.shadowPath = CGPath(rect: layer.bounds, transform: nil)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    func setActive(_ active: Bool) {
        applyGlow(active: active)
    }

    /// Direct CALayer mapping of CSS `box-shadow: 0 0 <radius> <color>` (no `border`).
    private func applyGlow(active: Bool) {
        guard let layer = imageView.layer else { return }
        layer.borderWidth = 0
        layer.shadowOffset = .zero
        layer.masksToBounds = false
        if active {
            layer.shadowColor = activeGlow.cgColor
            layer.shadowRadius = 6 // blur-radius (half of prior 12)
            layer.shadowOpacity = 0.95
        } else {
            layer.shadowColor = inactiveGlow.cgColor
            layer.shadowRadius = 4
            layer.shadowOpacity = 0.55
        }
        layer.shadowPath = CGPath(rect: layer.bounds, transform: nil)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        window?.performDrag(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let pad = PinPanel.chromePadding
        let imageRect = bounds.insetBy(dx: pad, dy: pad)
        guard imageRect.contains(point) else { return nil }
        return self
    }
}
