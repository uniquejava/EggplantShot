import AppKit

extension Annotation {
    /// Convenience for the text tool.
    init(id: UUID = UUID(), string: String, rect: CGRect, style: TextStyle) {
        self.id = id
        self.payload = .text(string: string, rect: rect, style: style)
    }

    var textStyle: TextStyle {
        get {
            if case .text(_, _, let style) = payload { return style }
            return .default
        }
        set {
            guard case .text(let string, let rect, _) = payload else { return }
            payload = .text(string: string, rect: rect, style: newValue)
        }
    }

    /// How `origin` maps onto the fitted text box (selection-local Cocoa points).
    enum TextRectAnchor {
        /// `origin` is the top-left (grow downward while editing).
        case topLeft
        /// `origin` is the left edge at the vertical center (click-to-place).
        case leadingMidY
    }

    /// Fitted rect for `string` with `style`, anchored at `origin`.
    /// Width grows with glyphs; wraps only when exceeding `maxWidth`.
    static func fittedTextRect(
        string: String,
        style: TextStyle,
        origin: CGPoint,
        maxWidth: CGFloat = 10_000,
        anchor: TextRectAnchor = .topLeft
    ) -> CGRect {
        let size = fittingTextSize(string: string, style: style, maxWidth: maxWidth)
        let y: CGFloat
        switch anchor {
        case .topLeft:
            y = origin.y - size.height
        case .leadingMidY:
            y = origin.y - size.height / 2
        }
        return CGRect(x: origin.x, y: y, width: size.width, height: size.height)
    }

    /// Box size: glyphs + tiny padding only; empty box is caret-wide. Soft-wrap past `maxWidth`.
    static func fittingTextSize(
        string: String,
        style: TextStyle,
        maxWidth: CGFloat = 10_000
    ) -> CGSize {
        let pad = style.textPadding
        let minH = ceil(style.makeFont().boundingRectForFont.height) + pad * 2
        if string.isEmpty {
            return CGSize(width: pad * 2 + TextStyle.caretWidth, height: minH)
        }
        let attributed = NSAttributedString(string: string, attributes: style.attributes())
        let natural = attributed.boundingRect(
            with: CGSize(width: 10_000, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let naturalW = ceil(natural.width) + pad * 2
        let naturalH = max(ceil(natural.height) + pad * 2, minH)
        if naturalW <= maxWidth {
            return CGSize(width: naturalW, height: naturalH)
        }
        let inner = max(maxWidth - pad * 2, 12)
        let wrapped = attributed.boundingRect(
            with: CGSize(width: inner, height: 10_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        return CGSize(
            width: maxWidth,
            height: max(ceil(wrapped.height) + pad * 2, minH)
        )
    }
}
