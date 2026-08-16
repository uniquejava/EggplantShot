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

    /// Apply `style` and re-fit the box from the current top-left (scroll-wheel / toolbar size).
    mutating func setTextStyleKeepingTopLeft(_ style: TextStyle, string: String? = nil) {
        guard case .text(let existing, let rect, _) = payload else { return }
        let text = string ?? existing
        let fitted = Annotation.fittedTextRect(
            string: text,
            style: style,
            origin: CGPoint(x: rect.minX, y: rect.maxY),
            anchor: .topLeft
        )
        payload = .text(string: text, rect: fitted, style: style)
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
        maxWidth: CGFloat = TextBoxMetrics.unboundedExtent,
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

    /// Box size: glyphs + padding; empty box is caret-wide. Soft-wrap past `maxWidth`.
    /// The arithmetic lives in `TextBoxMetrics` so the live field editor computes the same box —
    /// only the *measurement* differs (see `AnnotationTextView.fittingSize`).
    static func fittingTextSize(
        string: String,
        style: TextStyle,
        maxWidth: CGFloat = TextBoxMetrics.unboundedExtent
    ) -> CGSize {
        let metrics = TextBoxMetrics(style: style, maxWidth: maxWidth)
        if string.isEmpty {
            return metrics.emptySize
        }
        let attributed = NSAttributedString(string: string, attributes: style.attributes())
        func extent(wrappingAt width: CGFloat) -> CGRect {
            attributed.boundingRect(
                with: CGSize(width: width, height: TextBoxMetrics.unboundedExtent),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
        }
        let natural = extent(wrappingAt: TextBoxMetrics.unboundedExtent)
        let size = metrics.size(glyphWidth: natural.width, glyphHeight: natural.height)
        guard metrics.needsWrap(size) else { return size }
        return metrics.wrappedSize(
            glyphHeight: extent(wrappingAt: metrics.innerWidthAtMaxWidth).height
        )
    }
}
