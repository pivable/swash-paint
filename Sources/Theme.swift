import AppKit

/// The few colours and shapes the window chrome uses, in one place.
///
/// Everything here is either a system colour or a dynamic one that answers for light and
/// dark itself, so nothing in the interface has to listen for an appearance change: AppKit
/// resolves these at draw time. The one thing that cannot be dynamic is a `CGColor` stored
/// on a layer, which is why the layer-backed views resolve through `resolved(_:in:)` and
/// redo it in `viewDidChangeEffectiveAppearance`.
enum Theme {
    /// Behind the canvas. A quiet neutral, a step away from the window colour in each
    /// appearance, so the paper reads as paper. The old flat 35% grey was the same in
    /// light and dark, and in light mode it made the window look like a hole.
    static let backdrop = NSColor(name: "PaintboxBackdrop") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.11, alpha: 1)
            : NSColor(white: 0.90, alpha: 1)
    }

    /// The soft shadow the canvas casts on the backdrop.
    static let canvasShadow = NSColor(name: "PaintboxCanvasShadow") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0, alpha: 0.55)
            : NSColor(white: 0, alpha: 0.30)
    }

    /// A tool tile at rest: barely there, so the selected one is what the eye finds.
    static let tileFill = NSColor(name: "PaintboxTileFill") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.05)
    }

    /// A tool tile under the pointer: a step up from nothing, a step down from the accent.
    static let tileHover = NSColor(name: "PaintboxTileHover") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.12)
            : NSColor(white: 0, alpha: 0.07)
    }

    /// The faint dot grid on the backdrop. Enough to say "a surface", never a pattern.
    static let backdropDot = NSColor(name: "PaintboxBackdropDot") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.09)
    }

    /// What a glass panel looks like where the real material cannot be drawn: in the
    /// pre-26 fallback's border, and in `--screenshot`, whose `cacheDisplay` renders
    /// Liquid Glass as an opaque white slab. These are measured off the real material
    /// over this app's backdrop, so a screenshot reads the way the window does.
    static let glassFill = NSColor(name: "PaintboxGlassFill") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.20, alpha: 0.82)
            : NSColor(white: 0.995, alpha: 0.80)
    }
    static let glassRim = NSColor(name: "PaintboxGlassRim") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.16)
            : NSColor(white: 0, alpha: 0.09)
    }
    static let glassSheen = NSColor(name: "PaintboxGlassSheen") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 1, alpha: 0.65)
    }
    static let glassShadow = NSColor(name: "PaintboxGlassShadow") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0, alpha: 0.50)
            : NSColor(white: 0, alpha: 0.16)
    }

    static let tileRadius: CGFloat = 10
    static let swatchRadius: CGFloat = 4
    /// The gap between a floating panel and the edge of the canvas area.
    static let panelInset: CGFloat = 14

    /// A dynamic colour as a `CGColor` for `view`'s current appearance.
    static func resolved(_ color: NSColor, in view: NSView) -> CGColor {
        var cg = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { cg = color.cgColor }
        return cg
    }
}

/// One tool in the dock: an SF Symbol on a rounded tile that fills with the system accent
/// colour when it is the current tool, and lifts a little under the pointer.
///
/// The key letter used to sit beside the symbol, in the same colour and weight, and it
/// read as part of the icon — "pencil P" looked like one glyph. The shortcut lives in
/// the tooltip and in the options island's keycap instead, where it reads as a key.
///
/// Still an `NSButton` — keyboard focus, tooltips, accessibility and the push-on-push-off
/// state all come with it — drawn borderless on a layer of its own.
final class ToolTileButton: NSButton {
    private var hovering = false { didSet { if hovering != oldValue { restyle() } } }
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = Theme.tileRadius
        layer?.cornerCurve = .continuous
        setButtonType(.pushOnPushOff)
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        title = ""
        font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    override var state: NSControl.StateValue { didSet { restyle() } }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    func restyle() {
        let on = state == .on
        let fill: NSColor = on ? .controlAccentColor : (hovering ? Theme.tileHover : .clear)
        layer?.backgroundColor = Theme.resolved(fill, in: self)
        contentTintColor = on ? .white : .labelColor
    }
}

/// A floating panel: Liquid Glass on macOS 26, the system's popover material before it.
///
/// The controls sit in `contentView`, a SIBLING laid over the material rather than a
/// child of it, so that the material can be swapped out from under them — which is what
/// `GlassSnapshot` does for `--screenshot` — without taking the controls with it.
///
/// The view is larger than the panel by `GlassPanel.outset` on every side, and draws the
/// panel's soft shadow into that margin itself. A layer shadow would be simpler and
/// `cacheDisplay` does not render layer shadows, so the screenshot would show the panels
/// pasted flat onto the canvas. Clicks in the margin fall through to the canvas.
class GlassPanel: NSView {
    static let outset: CGFloat = 24

    let contentView = NSView()
    private(set) var material: NSView!
    var cornerRadius: CGFloat { didSet { applyShape() } }

    /// Where the panel itself is, in the superview's coordinates. `frame` is this plus
    /// the shadow margin.
    var shapeFrame: CGRect {
        get { frame.insetBy(dx: Self.outset, dy: Self.outset) }
        set { frame = newValue.insetBy(dx: -Self.outset, dy: -Self.outset) }
    }
    var shapeBounds: CGRect { bounds.insetBy(dx: Self.outset, dy: Self.outset) }

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: CGRect(x: 0, y: 0, width: 2 * Self.outset + 40, height: 2 * Self.outset + 40))
        material = Self.makeMaterial(frame: shapeBounds, cornerRadius: cornerRadius)
        material.autoresizingMask = [.width, .height]
        addSubview(material)
        contentView.frame = shapeBounds
        contentView.autoresizingMask = [.width, .height]
        addSubview(contentView)
        applyShape()
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Whether the real Liquid Glass is in use. False on macOS 14 and 15, and on a
    /// machine whose compiler predates the macOS 26 SDK, where the symbol does not exist.
    static var usesLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    private static func makeMaterial(frame: NSRect, cornerRadius: CGFloat) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            return glass
        }
        #endif
        let v = NSVisualEffectView(frame: frame)
        v.material = .popover
        v.blendingMode = .withinWindow
        v.state = .active
        v.wantsLayer = true
        return v
    }

    private func applyShape() {
        needsDisplay = true
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = material as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
            return
        }
        #endif
        // The fallback gets a hairline rim of its own, which Liquid Glass brings itself.
        material.wantsLayer = true
        material.layer?.cornerRadius = cornerRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = Theme.resolved(Theme.glassRim, in: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        // The shadow only, outside the shape: inside it the material has to be seen through.
        let shape = NSBezierPath(roundedRect: shapeBounds, xRadius: cornerRadius, yRadius: cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath(rect: bounds)
        clip.append(shape.reversed)
        clip.addClip()
        let shadow = NSShadow()
        shadow.shadowColor = Theme.glassShadow
        shadow.shadowBlurRadius = 16
        shadow.shadowOffset = CGSize(width: 0, height: -4)
        shadow.set()
        NSColor.black.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinates.
        let local = convert(point, from: superview)
        let shape = NSBezierPath(roundedRect: shapeBounds, xRadius: cornerRadius, yRadius: cornerRadius)
        guard shape.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyShape()
    }
}

/// `cacheDisplay`, which is all `--screenshot` has on a machine where `screencapture`
/// returns black, cannot render Liquid Glass: every `NSGlassEffectView` comes out as an
/// opaque white slab. In dark mode that slab sits under the toolbar's white glyphs and
/// every toolbar button became a white blob, which is what the owner was shown. The app
/// on screen never looked like that. So before a snapshot each glass view is hidden and
/// a drawn stand-in of the same shape takes its place, in the colours the glass actually
/// shows over this window; afterwards everything is put back.
enum GlassSnapshot {
    /// Swaps every glass view under `root` for a stand-in, returning how many it swapped
    /// and how to undo it.
    static func substitute(in root: NSView) -> (swapped: Int, restore: () -> Void) {
        var undo: [() -> Void] = []
        func walk(_ v: NSView) {
            if isGlass(v), !v.isHidden, let parent = v.superview {
                let stand = GlassStandIn(frame: v.frame, cornerRadius: radius(of: v))
                stand.appearance = v.effectiveAppearance
                parent.addSubview(stand, positioned: .below, relativeTo: v)
                v.isHidden = true
                undo.append { v.isHidden = false; stand.removeFromSuperview() }
                return
            }
            for sub in v.subviews { walk(sub) }
        }
        walk(root)
        return (undo.count, { undo.forEach { $0() } })
    }

    static func isGlass(_ v: NSView) -> Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), v is NSGlassEffectView { return true }
        #endif
        // A GlassPanel's own fallback material is real and renders, but flat; the
        // stand-in is closer to what is on screen, so it is swapped too.
        return v.superview is GlassPanel && v is NSVisualEffectView
    }

    private static func radius(of v: NSView) -> CGFloat {
        var r: CGFloat = 0
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let g = v as? NSGlassEffectView { r = g.cornerRadius }
        #endif
        if let panel = v.superview as? GlassPanel { r = panel.cornerRadius }
        // The toolbar's platters leave the radius at 0 and are capsules.
        return r > 0 ? r : min(v.frame.width, v.frame.height) / 2
    }
}

/// The drawn likeness of a glass panel: a translucent fill, a sheen along the top, a
/// hairline rim and a soft shadow.
final class GlassStandIn: NSView {
    let cornerRadius: CGFloat
    init(frame: NSRect, cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: frame)
        autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = min(cornerRadius, r.height / 2, r.width / 2)
        let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        Theme.glassFill.setFill()
        path.fill()
        path.addClip()
        // The sheen: light catching the upper edge, fading out by the middle.
        let sheen = NSGradient(colors: [Theme.glassSheen, Theme.glassSheen.withAlphaComponent(0)])
        sheen?.draw(in: CGRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2), angle: -90)
        NSGraphicsContext.restoreGraphicsState()
        Theme.glassRim.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
