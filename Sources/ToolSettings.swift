import AppKit

enum Tool: String, CaseIterable {
    case pencil, brush, eraser, line, arrow, rectangle, ellipse, bucket, eyedropper, text, select, wand

    var title: String {
        switch self {
        case .pencil: return "Pencil"
        case .brush: return "Brush"
        case .eraser: return "Eraser"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .bucket: return "Paint Bucket"
        case .eyedropper: return "Eyedropper"
        case .text: return "Text"
        case .select: return "Rectangular Selection"
        case .wand: return "Magic Wand"
        }
    }

    /// Single-key shortcut, shown in the Tools menu, the dock tooltips and the options island.
    var key: String {
        switch self {
        case .pencil: return "p"
        case .brush: return "b"
        case .eraser: return "e"
        case .line: return "l"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "o"
        case .bucket: return "f"
        case .eyedropper: return "i"
        case .text: return "t"
        case .select: return "s"
        case .wand: return "w"
        }
    }

    var symbolName: String {
        switch self {
        case .pencil: return "pencil"
        case .brush: return "paintbrush.pointed.fill"
        case .eraser: return "eraser.fill"
        case .line: return "line.diagonal"
        case .arrow: return "line.diagonal.arrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .bucket: return "drop.fill"
        case .eyedropper: return "eyedropper"
        case .text: return "textformat"
        case .select: return "dot.squareshape.split.2x2"
        case .wand: return "wand.and.stars"
        }
    }

    var usesShapeStyle: Bool { self == .rectangle || self == .ellipse }

    /// The two tools that drag out a shape from a start point, share the line width,
    /// and preview the same way.
    var isLineLike: Bool { self == .line || self == .arrow }
}

enum ShapeStyle: Int {
    case outline = 0, filled = 1, both = 2
}

/// Shared, observable-by-callback bag of everything the tools need.
final class ToolSettings {
    var tool: Tool = .pencil { didSet { if tool != oldValue { notify() } } }
    var foreground: NSColor = .black { didSet { notify() } }
    var background: NSColor = .white { didSet { notify() } }
    var brushSize: CGFloat = 16 { didSet { notify() } }
    var strokeWidth: CGFloat = 2 { didSet { notify() } }
    var tolerance: Int = 32 { didSet { notify() } }
    /// Kept separate from the bucket's tolerance on purpose: people want a tight fill
    /// and a loose selection at the same time, and sharing one slider makes them fight.
    var wandTolerance: Int = 32 { didSet { notify() } }
    var shapeStyle: ShapeStyle = .outline { didSet { notify() } }
    var font: NSFont = NSFont.systemFont(ofSize: 36) { didSet { notify() } }

    var onChange: (() -> Void)?
    private func notify() { onChange?() }

    func swapColors() {
        let f = foreground
        foreground = background
        background = f
    }
}

/// The palette: a row of neutrals, the system's own hues, and a row of deeper and softer
/// ones — twenty-four colours, twelve to a row in the colour capsule.
///
/// It used to be MS Paint's twenty, in MS Paint's order, and the pure primaries of a 1990s
/// palette were half of why the app looked its age. Black and white stay exact, because
/// people draw with them and expect 0 and 255.
enum StandardPalette {
    private static func c(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static let colors: [NSColor] = [
        // Neutrals, then the warm half of the system hues.
        0x000000, 0x3A3A3C, 0x8E8E93, 0xD1D1D6, 0xFFFFFF, 0xFF3B30,
        0xFF9500, 0xFFCC00, 0x34C759, 0x00C7BE, 0x32ADE6, 0x007AFF,
        // The cool half, then deeper and softer tones.
        0x5856D6, 0xAF52DE, 0xFF2D55, 0xA2845E, 0x1E3A8A, 0x14532D,
        0x7F1D1D, 0xFFD6A5, 0xFDCFE8, 0xCDB4F6, 0xBDE0FE, 0xC7F0D8,
    ].map(c)

    /// The ones on show while the capsule is closed: what most drawings are made of.
    static let quick: [NSColor] = [0x000000, 0xFFFFFF, 0xFF3B30, 0xFF9500, 0xFFCC00,
                                   0x34C759, 0x007AFF, 0xAF52DE].map(c)
}

/// Every SF Symbol the interface asks for, in one place so the self-test can check
/// they all resolve on this system. A missing symbol shows up as a blank button.
enum Symbols {
    static let crop = "crop"
    static let resize = "arrow.up.left.and.down.right.magnifyingglass"
    static let canvasSize = "squareshape.dashed.squareshape"
    static let flipH = "arrow.left.and.right.righttriangle.left.righttriangle.right"
    static let flipV = "arrow.up.and.down.righttriangle.up.righttriangle.down"
    static let rotateCW = "rotate.right"
    static let rotateCCW = "rotate.left"
    static let removeBG = "person.and.background.dotted"
    static let zoomIn = "plus.magnifyingglass"
    static let zoomOut = "minus.magnifyingglass"
    static let zoomFit = "arrow.up.left.and.arrow.down.right"
    static let undo = "arrow.uturn.backward"
    static let redo = "arrow.uturn.forward"
    static let blur = "wind"
    static let pixelate = "squareshape.split.3x3"
    static let adjust = "slider.horizontal.3"
    static let grayscale = "circle.lefthalf.filled"
    static let invert = "circle.righthalf.filled"
    static let trim = "scissors"

    static let all: [String] = [crop, resize, canvasSize, flipH, flipV, rotateCW, rotateCCW,
                                removeBG, zoomIn, zoomOut, zoomFit, undo, redo,
                                blur, pixelate, adjust, grayscale, invert, trim]
        + Tool.allCases.map { $0.symbolName }
}
