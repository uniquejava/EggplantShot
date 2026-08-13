import AppKit

// MARK: - Text editing bridge

/// Routes `NSTextView` delegate callbacks back to the overlay controller.
@MainActor
final class TextEditingBridge: NSObject, NSTextViewDelegate {
    static let shared = TextEditingBridge()
    weak var owner: SelectionOverlayController?

    func textDidChange(_ notification: Notification) {
        owner?.resizeTextEditorToFit()
    }

    /// AppKit resets to arrow when cursor rects are invalidated (e.g. caret blink); re-apply ours.
    func reassertOverlayCursor() {
        owner?.reassertOverlayCursor()
    }
}

/// 1 device-pixel stroke, matching the edit-frame hairline.
private func textHairlineWidth(in view: NSView) -> CGFloat {
    1 / max(view.window?.backingScaleFactor ?? 2, 1)
}

/// Transparent host that paints a Snipaste-style hairline edit frame (no fill).
/// Stroke is white on dark backdrops, black on light — matches the insertion point.
final class TextEditChromeView: NSView {
    var strokeColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override func resetCursorRects() {}
    override func cursorUpdate(with event: NSEvent) {
        TextEditingBridge.shared.reassertOverlayCursor()
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = textHairlineWidth(in: self)
        strokeColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: w / 2, dy: w / 2))
        border.lineWidth = w
        border.stroke()
    }
}

/// 1 device-pixel caret, same stroke as `TextEditChromeView`.
private final class HairlineCaretView: NSView {
    var color: NSColor = .white {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        bounds.fill()
    }
}

/// Text mark field editor with an isolated undo stack (avoids poisoning the app-wide
/// `UndoManager` with `_undoRedoTextOperation:` targets that outlive the view).
final class AnnotationTextView: NSTextView {
    private let isolatedUndoManager = UndoManager()
    private let hairlineCaret = HairlineCaretView()
    private var caretBlinkTimer: Timer?
    private var caretOn = true
    private var lastCaretRect: NSRect = .zero
    /// Live-fit the chrome; IME marked text does not post `textDidChange` until commit.
    var onNeedsFit: (() -> Void)?

    /// TextKit 1 stack so `drawInsertionPoint` / the blink timer stay on the classic path.
    /// (`init(frame:)` on macOS 13+ otherwise installs TextKit 2 + `NSTextInsertionIndicator`.)
    override init(frame frameRect: NSRect) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: frameRect.size)
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)
        super.init(frame: frameRect, textContainer: textContainer)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        hairlineCaret.isHidden = true
        addSubview(hairlineCaret)
    }

    override var undoManager: UndoManager? { isolatedUndoManager }
    override var isOpaque: Bool { false }

    /// Overlay drives the cursor via hit-testing; do not let TextKit install an I-beam over the border.
    override func resetCursorRects() {}
    override func cursorUpdate(with event: NSEvent) {
        TextEditingBridge.shared.reassertOverlayCursor()
    }

    override var insertionPointColor: NSColor! {
        get { super.insertionPointColor }
        set {
            super.insertionPointColor = newValue
            hairlineCaret.color = newValue
        }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if subview is NSTextInsertionIndicator {
            hideSystemInsertionIndicator()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopCaretBlink()
        }
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        captureSystemCaretRect()
        hideSystemInsertionIndicator()
        syncHairlineCaret(restartBlink: restartFlag)
    }

    override func layout() {
        super.layout()
        captureSystemCaretRect()
        hideSystemInsertionIndicator()
        syncHairlineCaret(restartBlink: false)
    }

    /// `NSTextInsertionIndicator` has no thickness API (SDK: color / displayMode only).
    /// Apple sizes the **height** from the frame and centers a system-styled bar in it —
    /// shrinking the frame does not make a hairline (and Sonoma does not clip to bounds).
    /// Do not call super — that would show the thick system bar.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn _: Bool) {
        lastCaretRect = rect
        hideSystemInsertionIndicator()
        hairlineCaret.color = color
        placeHairlineCaret(in: rect)
        // Blink is owned by `caretBlinkTimer`, not `turnedOn` — otherwise the two fight.
    }

    private func captureSystemCaretRect() {
        if let indicator = subviews.compactMap({ $0 as? NSTextInsertionIndicator }).first,
           indicator.frame.height > 0.5 {
            lastCaretRect = indicator.frame
        }
    }

    private func hideSystemInsertionIndicator() {
        var foundIndicator = false
        for sub in subviews {
            guard let indicator = sub as? NSTextInsertionIndicator else { continue }
            foundIndicator = true
            if indicator.displayMode != .hidden {
                indicator.displayMode = .hidden
            }
            indicator.isHidden = true
            indicator.alphaValue = 0
        }
        if foundIndicator, subviews.last !== hairlineCaret {
            addSubview(hairlineCaret, positioned: .above, relativeTo: nil)
        }
    }

    private func syncHairlineCaret(restartBlink: Bool) {
        hideSystemInsertionIndicator()
        guard shouldDrawInsertionPoint, let rect = insertionCaretRect() else {
            stopCaretBlink()
            hairlineCaret.isHidden = true
            return
        }
        hairlineCaret.color = insertionPointColor
        placeHairlineCaret(in: rect)
        if restartBlink || caretBlinkTimer == nil {
            startCaretBlink()
        } else {
            hairlineCaret.isHidden = !caretOn
        }
    }

    private func placeHairlineCaret(in rect: NSRect) {
        let w = textHairlineWidth(in: self)
        let scale = max(window?.backingScaleFactor ?? 2, 1)
        // System indicator is a narrow bar (use midX). Line-fragment fallbacks are wide (use minX).
        let caretX = rect.width <= 4 ? rect.midX - w / 2 : rect.minX
        let x = (caretX * scale).rounded() / scale
        hairlineCaret.frame = NSRect(x: x, y: rect.minY, width: w, height: max(rect.height, 1))
    }

    /// Prefer the last system caret rect (captured before hiding the indicator).
    private func insertionCaretRect() -> NSRect? {
        if lastCaretRect.height > 0.5 {
            return lastCaretRect
        }
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let range = selectedRange()
        guard range.length == 0 else { return nil }
        let length = textStorage?.length ?? 0
        let extra = lm.extraLineFragmentRect
        if range.location >= length, extra.height > 0 {
            var r = extra.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            r.size.width = 1
            return r
        }
        guard length > 0 else { return nil }
        let index = min(range.location, length - 1)
        let glyph = lm.glyphIndexForCharacter(at: index)
        var rect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let loc = lm.location(forGlyphAt: glyph)
        rect.origin.x += loc.x + textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        if range.location >= length {
            rect.origin.x += lm.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1),
                in: tc
            ).width
        }
        rect.size.width = 1
        return rect
    }

    private func startCaretBlink() {
        caretOn = true
        hairlineCaret.isHidden = false
        caretBlinkTimer?.invalidate()
        let timer = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard self.shouldDrawInsertionPoint else {
                    self.hairlineCaret.isHidden = true
                    return
                }
                self.caretOn.toggle()
                self.hairlineCaret.isHidden = !self.caretOn
                // Toggling the caret view invalidates cursor rects → AppKit arrow unless we re-apply.
                TextEditingBridge.shared.reassertOverlayCursor()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        caretBlinkTimer = timer
    }

    private func stopCaretBlink() {
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
        caretOn = true
        hairlineCaret.isHidden = true
    }

    func clearIsolatedUndo() {
        isolatedUndoManager.removeAllActions()
        stopCaretBlink()
    }

    override func didChangeText() {
        super.didChangeText()
        onNeedsFit?()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onNeedsFit?()
    }

    override func unmarkText() {
        super.unmarkText()
        onNeedsFit?()
    }

    /// Size from laid-out glyphs (includes IME preedit). Width is glyphs + padding only.
    func fittingSize(
        padding: CGFloat,
        caretWidth: CGFloat,
        minHeight: CGFloat,
        maxWidth: CGFloat
    ) -> CGSize {
        if string.isEmpty, markedRange().length == 0 {
            let caret = textHairlineWidth(in: self)
            return CGSize(width: padding * 2 + caret, height: minHeight)
        }
        guard let lm = layoutManager, let tc = textContainer else {
            return CGSize(width: padding * 2 + caretWidth, height: minHeight)
        }
        let saved = tc.containerSize
        tc.containerSize = CGSize(width: 10_000, height: 10_000)
        lm.ensureLayout(for: tc)
        var used = lm.usedRect(for: tc)
        let glyphW = max(ceil(used.maxX), caretWidth)
        var width = glyphW + padding * 2
        var height = ceil(used.height) + padding * 2
        if width > maxWidth {
            let inner = max(maxWidth - padding * 2, 12)
            tc.containerSize = CGSize(width: inner, height: 10_000)
            lm.ensureLayout(for: tc)
            used = lm.usedRect(for: tc)
            width = maxWidth
            height = ceil(used.height) + padding * 2
        }
        tc.containerSize = saved
        return CGSize(
            width: width,
            height: max(height, minHeight)
        )
    }
}
