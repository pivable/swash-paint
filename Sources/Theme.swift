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

    static let tileRadius: CGFloat = 8
    static let swatchRadius: CGFloat = 4

    /// A dynamic colour as a `CGColor` for `view`'s current appearance.
    static func resolved(_ color: NSColor, in view: NSView) -> CGColor {
        var cg = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { cg = color.cgColor }
        return cg
    }
}

/// One tool in the palette: an SF Symbol and its key letter on a rounded tile that fills
/// with the system accent colour when it is the current tool.
///
/// Still an `NSButton` — keyboard focus, tooltips, accessibility and the push-on-push-off
/// state all come with it — drawn borderless on a layer of its own instead of with the
/// textured bezel, which is the look macOS dropped several releases ago.
final class ToolTileButton: NSButton {
    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = Theme.tileRadius
        layer?.cornerCurve = .continuous
        setButtonType(.pushOnPushOff)
        imagePosition = .imageLeading
        imageHugsTitle = true
        font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    override var state: NSControl.StateValue { didSet { restyle() } }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    func restyle() {
        let on = state == .on
        layer?.backgroundColor = Theme.resolved(on ? .controlAccentColor : Theme.tileFill, in: self)
        contentTintColor = on ? .white : .labelColor
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: font ?? NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: on ? NSColor.white : NSColor.secondaryLabelColor,
        ])
    }
}
