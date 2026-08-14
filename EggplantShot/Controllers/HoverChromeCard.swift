import AppKit

final class HoverChromeCard: NSView {
    private static let cornerRadius: CGFloat = 6
    private static let accentHeight: CGFloat = 2
    /// If the tool sits within this inset of a side, extend the bar into that rounded corner.
    private static let edgeExtendSlop: CGFloat = 10

    let chrome = NSView(frame: .zero)
    let accent = NSView(frame: .zero)
    /// Shared custom tooltip (native tooltips fail on the non-activating panel).
    var tooltip: RefineToolbarTooltip?
    var trackingArea: NSTrackingArea?
    private weak var hoveredButton: NSButton?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        translatesAutoresizingMaskIntoConstraints = false

        chrome.wantsLayer = true
        chrome.layer?.backgroundColor = NSColor.white.cgColor
        chrome.layer?.cornerRadius = Self.cornerRadius
        chrome.layer?.masksToBounds = true
        chrome.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chrome)

        accent.wantsLayer = true
        accent.layer?.backgroundColor = NSColor.systemBlue.cgColor
        accent.alphaValue = 0
        // Frame-positioned under the hovered tool (not Auto Layout).
        accent.translatesAutoresizingMaskIntoConstraints = true
        chrome.addSubview(accent)

        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: trailingAnchor),
            chrome.topAnchor.constraint(equalTo: topAnchor),
            chrome.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func installContent(_ child: NSView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(child, positioned: .below, relativeTo: accent)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
            child.topAnchor.constraint(equalTo: chrome.topAnchor),
            child.bottomAnchor.constraint(equalTo: chrome.bottomAnchor),
        ])
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // Nonactivating toolbar panel — same as palette / mosaic slider.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        syncHover(from: event)
    }

    override func mouseMoved(with event: NSEvent) {
        syncHover(from: event)
    }

    override func mouseExited(with event: NSEvent) {
        setHoveredButton(nil)
    }

    override func mouseDown(with event: NSEvent) {
        tooltip?.hide()
        super.mouseDown(with: event)
    }

    override func layout() {
        super.layout()
        if let hoveredButton {
            positionAccent(under: hoveredButton, animated: false)
        }
    }

    func syncHover(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        setHoveredButton(toolButton(at: point))
    }

    func toolButton(at point: CGPoint) -> NSButton? {
        let local = chrome.convert(point, from: self)
        guard let hit = chrome.hitTest(local) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== chrome {
            if let button = current as? NSButton {
                return button
            }
            view = current.superview
        }
        return nil
    }

    func setHoveredButton(_ button: NSButton?) {
        if hoveredButton === button { return }
        hoveredButton = button
        tooltip?.handleHover(button)
        if let button {
            positionAccent(under: button, animated: true)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().alphaValue = 1
            }
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().alphaValue = 0
            }
        }
    }

    func positionAccent(under button: NSButton, animated: Bool) {
        let buttonRect = button.convert(button.bounds, to: chrome)
        var x = buttonRect.minX
        var width = buttonRect.width
        let bounds = chrome.bounds

        // Snipaste: first / last tools extend the bar into the card’s rounded corners.
        if buttonRect.minX <= Self.edgeExtendSlop {
            width += x
            x = 0
        }
        if buttonRect.maxX >= bounds.width - Self.edgeExtendSlop {
            width = bounds.width - x
        }

        let target = CGRect(
            x: x,
            y: 0,
            width: max(width, 1),
            height: Self.accentHeight
        )
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                accent.animator().frame = target
            }
        } else {
            accent.frame = target
        }
    }
}

