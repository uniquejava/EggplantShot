import AppKit

final class PinPanel: NSPanel {
    /// Room outside the bitmap for the soft outer glow (must be ≥ blur radius).
    static let chromePadding: CGFloat = 10

    private let itemID: UUID
    private let image: NSImage
    private let onClose: (UUID) -> Void
    private let chromeView: PinChromeView
    private var keyObservers: [NSObjectProtocol] = []
    private var staysOnTop = true

    init(itemID: UUID, image: NSImage, frame: CGRect, onClose: @escaping (UUID) -> Void) {
        self.itemID = itemID
        self.image = image
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
        chrome.onCopy = { [weak self] in
            self?.copyImage()
        }
        chrome.onScaleChange = { [weak self] scale in
            self?.applyScale(scale)
        }
        chrome.menuBuilder = { [weak self] in
            self?.makeContextMenu()
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

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(withTitle: L10n.tr("Copy Image"), action: #selector(copyImage), keyEquivalent: "c")
            .target = self
        menu.addItem(withTitle: L10n.tr("Save Image As…"), action: #selector(saveImageAs), keyEquivalent: "")
            .target = self

        menu.addItem(.separator())

        let stay = menu.addItem(withTitle: L10n.tr("Stay on Top"), action: #selector(toggleStayOnTop), keyEquivalent: "")
        stay.target = self
        stay.state = staysOnTop ? .on : .off

        let shadow = menu.addItem(withTitle: L10n.tr("Shadow"), action: #selector(toggleShadow), keyEquivalent: "")
        shadow.target = self
        shadow.state = chromeView.shadowEnabled ? .on : .off

        menu.addItem(.separator())

        menu.addItem(withTitle: L10n.tr("Close"), action: #selector(closePin), keyEquivalent: "")
            .target = self

        menu.addItem(.separator())

        let size = menu.addItem(withTitle: pixelSizeLabel(), action: nil, keyEquivalent: "")
        size.isEnabled = false

        return menu
    }

    private func pixelSizeLabel() -> String {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
        }
        return "\(Int(image.size.width.rounded())) × \(Int(image.size.height.rounded()))"
    }

    @objc private func copyImage() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    @objc private func saveImageAs() {
        ImageFileSaver.saveInteractive(image)
    }

    @objc private func toggleStayOnTop() {
        staysOnTop.toggle()
        level = staysOnTop ? .statusBar : .normal
        orderFrontRegardless()
    }

    @objc private func toggleShadow() {
        chromeView.shadowEnabled.toggle()
        chromeView.setActive(isKeyWindow)
    }

    @objc private func closePin() {
        onClose(itemID)
    }

    /// Resize the panel around its center so the pin stays put while zooming.
    private func applyScale(_ scale: CGFloat) {
        let pad = Self.chromePadding
        let imageSize = CGSize(
            width: max(image.size.width * scale, 1),
            height: max(image.size.height * scale, 1)
        )
        let newSize = CGSize(width: imageSize.width + pad * 2, height: imageSize.height + pad * 2)
        var frame = self.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        frame.size = newSize
        frame.origin = CGPoint(x: center.x - newSize.width / 2, y: center.y - newSize.height / 2)
        setFrame(frame, display: true)
    }
}

/// Image + Snipaste-style outer glow (CSS `box-shadow: 0 0 blur color` — no hard border).
private final class PinChromeView: NSView {
    var onDoubleClick: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMouseDown: (() -> Void)?
    var onCopy: (() -> Void)?
    var onScaleChange: ((CGFloat) -> Void)?
    var menuBuilder: (() -> NSMenu?)?
    var shadowEnabled = true

    private let imageView: NSImageView
    private let zoomLabel: NSTextField
    private var scale: CGFloat = 1.0
    private var scrollAccum: CGFloat = 0
    private var hideZoomWorkItem: DispatchWorkItem?

    private static let zoomStep: CGFloat = 0.1
    private static let minScale: CGFloat = 0.1
    private static let maxScale: CGFloat = 10.0
    private static let zoomBadgeDuration: TimeInterval = 0.6
    private static let preciseScrollThreshold: CGFloat = 12

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

        zoomLabel = NSTextField(labelWithString: "100%")
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        zoomLabel.textColor = .white
        zoomLabel.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        zoomLabel.drawsBackground = true
        zoomLabel.isBezeled = false
        zoomLabel.isEditable = false
        zoomLabel.isSelectable = false
        zoomLabel.alignment = .center
        zoomLabel.wantsLayer = true
        zoomLabel.layer?.cornerRadius = 4
        zoomLabel.layer?.masksToBounds = true
        zoomLabel.alphaValue = 0
        zoomLabel.isHidden = true

        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(imageView)
        addSubview(zoomLabel)
        imageView.autoresizingMask = [.width, .height]
        applyGlow(active: true)
        layoutZoomLabel()
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
        layoutZoomLabel()
    }

    private func layoutZoomLabel() {
        let pad = PinPanel.chromePadding
        let inset: CGFloat = 8
        zoomLabel.sizeToFit()
        var labelFrame = zoomLabel.frame
        labelFrame.size.width += 10
        labelFrame.size.height += 4
        // Inner top-left of the bitmap (AppKit y-up).
        labelFrame.origin = CGPoint(
            x: pad + inset,
            y: bounds.height - pad - inset - labelFrame.height
        )
        zoomLabel.frame = labelFrame
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
        guard shadowEnabled else {
            layer.shadowOpacity = 0
            layer.shadowPath = nil
            return
        }
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

    override func menu(for event: NSEvent) -> NSMenu? {
        menuBuilder?()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        if event.clickCount >= 2 {
            onDoubleClick?()
            return
        }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        guard dy != 0 else {
            super.scrollWheel(with: event)
            return
        }

        if event.hasPreciseScrollingDeltas {
            scrollAccum += dy
            let threshold = Self.preciseScrollThreshold
            while scrollAccum >= threshold {
                scrollAccum -= threshold
                applyZoomStep(+Self.zoomStep)
            }
            while scrollAccum <= -threshold {
                scrollAccum += threshold
                applyZoomStep(-Self.zoomStep)
            }
        } else if dy > 0 {
            applyZoomStep(+Self.zoomStep)
        } else {
            applyZoomStep(-Self.zoomStep)
        }
    }

    private func applyZoomStep(_ delta: CGFloat) {
        let next = min(Self.maxScale, max(Self.minScale, scale + delta))
        guard abs(next - scale) > 0.0001 else { return }
        scale = (next * 10).rounded() / 10
        onScaleChange?(scale)
        showZoomBadge()
    }

    private func showZoomBadge() {
        let percent = Int((scale * 100).rounded())
        zoomLabel.stringValue = "\(percent)%"
        zoomLabel.isHidden = false
        layoutZoomLabel()

        hideZoomWorkItem?.cancel()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            zoomLabel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                self.zoomLabel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                self?.zoomLabel.isHidden = true
            })
        }
        hideZoomWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.zoomBadgeDuration, execute: work)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        // ⌘C copies the pinned image (matches context-menu shortcut).
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopy?()
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
