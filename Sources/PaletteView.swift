import AppKit

/// A round colour chip that reports left/right clicks separately.
final class SwatchButton: NSView {
    var color: NSColor { didSet { needsDisplay = true } }
    var onLeft: ((NSColor) -> Void)?
    var onRight: ((NSColor) -> Void)?
    /// Ringed in the accent colour: this is the colour the next stroke is drawn in.
    var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true } } }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        // A hairline in the system separator colour, so white still has an edge on light
        // glass and black still has one on dark glass.
        let inset: CGFloat = isSelected ? 4 : 3
        let r = bounds.insetBy(dx: inset, dy: inset)
        let p = NSBezierPath(ovalIn: r)
        color.setFill()
        p.fill()
        NSColor.separatorColor.setStroke()
        p.lineWidth = 1
        p.stroke()
        if isSelected {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.25, dy: 1.25))
            ring.lineWidth = 1.5
            NSColor.controlAccentColor.setStroke()
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) { onLeft?(color) }
    override func rightMouseDown(with event: NSEvent) { onRight?(color) }
}

/// The two colours in play: the line colour in front, the second colour behind it.
final class ColorWellsView: NSView {
    var foreground: NSColor = .black { didSet { needsDisplay = true } }
    var background: NSColor = .white { didSet { needsDisplay = true } }
    var onPickForeground: (() -> Void)?
    var onPickBackground: (() -> Void)?

    static let size = CGSize(width: 42, height: 38)
    private var fgRect: CGRect { CGRect(x: 2, y: bounds.height - 28, width: 26, height: 26) }
    private var bgRect: CGRect { CGRect(x: 14, y: 2, width: 26, height: 26) }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        func well(_ r: CGRect, _ c: NSColor) {
            let outer = NSBezierPath(ovalIn: r.insetBy(dx: -2, dy: -2))
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = CGSize(width: 0, height: -1)
            shadow.set()
            NSColor.white.setFill(); outer.fill()
            NSGraphicsContext.restoreGraphicsState()
            let inner = NSBezierPath(ovalIn: r)
            NSGraphicsContext.saveGraphicsState()
            inner.addClip()
            // A checkerboard under the colour, so a colour with alpha below 1 — which the
            // system picker offers by default, and which the eyedropper hands you from any
            // soft edge — LOOKS translucent. Painted flat on white it looked like an
            // ordinary pale colour, and the user had no way to tell why their strokes were
            // coming out faint or not at all.
            NSColor.white.setFill(); r.fill()
            NSColor(white: 0.84, alpha: 1).setFill()
            let square: CGFloat = 5
            var y = r.minY
            while y < r.maxY {
                var x = r.minX
                while x < r.maxX {
                    if (Int((x - r.minX) / square) + Int((y - r.minY) / square)) % 2 == 1 {
                        CGRect(x: x, y: y, width: min(square, r.maxX - x),
                               height: min(square, r.maxY - y)).fill()
                    }
                    x += square
                }
                y += square
            }
            c.setFill(); r.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: 0, alpha: 0.12).setStroke()
            inner.lineWidth = 0.5; inner.stroke()
        }
        well(bgRect, background)
        well(fgRect, foreground)
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if fgRect.insetBy(dx: -2, dy: -2).contains(p) { onPickForeground?() }
        else if bgRect.insetBy(dx: -2, dy: -2).contains(p) { onPickBackground?() }
    }
}
