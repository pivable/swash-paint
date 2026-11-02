import AppKit

// The three floating panels that replaced the fixed sidebar: the tool dock at the left
// edge of the canvas, the options island across the top, and the colour capsule along
// the bottom. The canvas has the whole width of the window under them.
//
// Why float them at all: a sidebar spends 156pt of every window on controls most of
// which do nothing for the tool in hand — four sliders were always on show and at most
// two ever mattered. Floating, the tools take one narrow column, the options shrink to
// exactly the current tool's, and the colours are one line until they are asked for.

/// The tools, one column of tiles on glass, grouped by what they do.
final class ToolDock: GlassPanel {
    /// Draw, shape, fill and type, select: the order of `Tool.allCases`, cut into groups.
    static let groups: [[Tool]] = [[.pencil, .brush, .eraser],
                                   [.line, .arrow, .rectangle, .ellipse],
                                   [.bucket, .eyedropper, .text],
                                   [.select, .wand]]

    static let tile: CGFloat = 36
    static let pad: CGFloat = 6
    static let gap: CGFloat = 2
    static let divider: CGFloat = 11

    private(set) var buttons: [Tool: ToolTileButton] = [:]
    private var dividers: [NSBox] = []
    private(set) var columns = 1
    var onSelect: ((Tool) -> Void)?

    init() {
        super.init(cornerRadius: (Self.tile + 2 * Self.pad) / 2)
        for tool in Tool.allCases {
            let b = ToolTileButton(frame: CGRect(x: 0, y: 0, width: Self.tile, height: Self.tile))
            if let img = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) {
                b.image = img
            } else {
                // Never a blank tile: the name's first letter if the symbol is missing.
                b.title = String(tool.title.prefix(1))
                b.imagePosition = .noImage
            }
            b.toolTip = Self.tooltip(for: tool)
            b.target = self
            b.action = #selector(clicked(_:))
            b.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            contentView.addSubview(b)
            buttons[tool] = b
        }
        for _ in 1..<Self.groups.count {
            let d = NSBox()
            d.boxType = .separator
            contentView.addSubview(d)
            dividers.append(d)
        }
        arrange(columns: 1)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// The tool's name and its key, which is where the key is shown now.
    static func tooltip(for tool: Tool) -> String { "\(tool.title)   \(tool.key.uppercased())" }

    /// How tall the dock is in `columns` columns.
    static func height(columns: Int) -> CGFloat {
        let rows = groups.map { ($0.count + columns - 1) / columns }
        let tiles = rows.reduce(0, +)
        let gaps = rows.map { max(0, $0 - 1) }.reduce(0, +)
        return 2 * pad + CGFloat(tiles) * tile + CGFloat(gaps) * gap + CGFloat(groups.count - 1) * divider
    }
    static func width(columns: Int) -> CGFloat {
        2 * pad + CGFloat(columns) * tile + CGFloat(columns - 1) * gap
    }

    /// The fewest columns that fit `height`. One on any ordinary window; two when the
    /// window has been made short, rather than tiles running off the bottom.
    static func columns(toFit height: CGFloat) -> Int {
        for c in 1...3 where Self.height(columns: c) <= height { return c }
        return 3
    }

    func arrange(columns: Int) {
        self.columns = columns
        let w = Self.width(columns: columns), h = Self.height(columns: columns)
        let origin = shapeFrame.origin
        shapeFrame = CGRect(origin: origin, size: CGSize(width: w, height: h))
        cornerRadius = columns == 1 ? w / 2 : 18
        // Laid out top-down in the content view's unflipped coordinates.
        var y = h - Self.pad
        for (gi, group) in Self.groups.enumerated() {
            for (i, tool) in group.enumerated() {
                let col = i % columns, row = i / columns
                buttons[tool]?.frame = CGRect(x: Self.pad + CGFloat(col) * (Self.tile + Self.gap),
                                              y: y - CGFloat(row + 1) * Self.tile - CGFloat(row) * Self.gap,
                                              width: Self.tile, height: Self.tile)
            }
            let rows = (group.count + columns - 1) / columns
            y -= CGFloat(rows) * Self.tile + CGFloat(max(0, rows - 1)) * Self.gap
            if gi < dividers.count {
                dividers[gi].frame = CGRect(x: Self.pad + 6, y: y - Self.divider / 2 - 0.5,
                                            width: w - 2 * Self.pad - 12, height: 1)
                y -= Self.divider
            }
        }
    }

    func refresh(current: Tool) {
        for (tool, b) in buttons { b.state = tool == current ? .on : .off }
    }

    @objc private func clicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = Tool(rawValue: raw) else { return }
        onSelect?(tool)
    }
}

/// A key drawn as a key: a small rounded cap, so "B" next to "Brush" reads as the
/// shortcut and not as part of the name.
final class KeycapView: NSView {
    var key: String = "" { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let p = NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5)
        NSColor.tertiaryLabelColor.withAlphaComponent(0.12).setFill()
        p.fill()
        NSColor.tertiaryLabelColor.setStroke()
        p.lineWidth = 0.5
        p.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let s = (key as NSString).size(withAttributes: attrs)
        (key as NSString).draw(at: CGPoint(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2),
                               withAttributes: attrs)
    }
}

/// What the current tool can be told, and nothing else: a pill across the top of the
/// canvas that says which tool is in hand and changes shape with it, the way the
/// Dynamic Island does.
final class OptionsIsland: GlassPanel {
    /// The settings a tool can have in the island, in the order they are shown.
    enum Option: String, CaseIterable {
        case size, width, style, tolerance, wandTolerance, font
    }

    static func options(for tool: Tool) -> [Option] {
        switch tool {
        case .brush, .eraser: return [.size]
        case .line, .arrow: return [.width]
        case .rectangle, .ellipse: return [.width, .style]
        case .bucket: return [.tolerance]
        case .wand: return [.wandTolerance]
        case .text: return [.font]
        case .pencil, .eyedropper, .select: return []
        }
    }

    /// For the tools with nothing to set, one true thing about using them.
    static func hint(for tool: Tool) -> String? {
        switch tool {
        case .pencil: return "Always 1 px, hard-edged"
        case .eyedropper: return "Right-click picks the second colour"
        case .select: return "Shift for a square"
        case .wand: return "⌥-click: every match"
        default: return nil
        }
    }

    // MARK: The shape-style segments
    //
    // "Outline" is the honest word for the first one and it does not fit. AppKit drew
    // "Out..." in a 46pt segment, which does not read as a choice, it reads as an
    // interface that was never finished. So the words are short enough to draw and the
    // full meaning is in the tooltip. `shapeStyleFits` is the rule, checked by the
    // self-test, so a future rewording cannot quietly reintroduce the ellipsis.

    /// What each segment says, and what it means on hover.
    static let shapeStyleSegments: [(label: String, help: String)] = [
        ("Line", "Outline only, drawn in the line colour"),
        ("Fill", "Filled, with no outline"),
        ("Both", "Filled, with an outline round it"),
    ]

    static let shapeStyleFont = NSFont.systemFont(ofSize: 11)

    /// One segment's width.
    static let shapeStyleSegmentWidth: CGFloat = 46

    /// Whether a label draws whole in one segment. The 12pt is the padding AppKit puts
    /// either side of a segment's text; a label that needs more than what is left is the
    /// one that comes out with an ellipsis.
    static func shapeStyleFits(_ label: String) -> Bool {
        shapeStyleTextWidth(label) + 12 <= shapeStyleSegmentWidth
    }

    static func shapeStyleTextWidth(_ label: String) -> CGFloat {
        (label as NSString).size(withAttributes: [.font: shapeStyleFont]).width
    }

    static let height: CGFloat = 44

    private let settings: ToolSettings
    private let icon = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    let keycap = KeycapView()
    private let rule = NSBox()
    let sizeSlider = NSSlider()
    let strokeSlider = NSSlider()
    let toleranceSlider = NSSlider()
    let wandSlider = NSSlider()
    private let sizeValue = NSTextField(labelWithString: "")
    private let strokeValue = NSTextField(labelWithString: "")
    private let toleranceValue = NSTextField(labelWithString: "")
    private let wandValue = NSTextField(labelWithString: "")
    private var captions: [Option: NSTextField] = [:]
    let styleControl = NSSegmentedControl(labels: OptionsIsland.shapeStyleSegments.map(\.label),
                                          trackingMode: .selectOne, target: nil, action: nil)
    let fontButton = NSButton(title: "", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "")

    var onInteraction: (() -> Void)?
    var onChooseFont: (() -> Void)?
    /// Called when the island's width changes, so the owner can re-centre it.
    var onResize: (() -> Void)?

    init(settings: ToolSettings) {
        self.settings = settings
        super.init(cornerRadius: Self.height / 2)
        icon.imageScaling = .scaleNone
        icon.contentTintColor = .controlAccentColor
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .labelColor
        rule.boxType = .separator
        hintLabel.font = NSFont.systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        for v in [icon, nameLabel, keycap, rule, hintLabel] as [NSView] { contentView.addSubview(v) }

        func slider(_ s: NSSlider, _ value: NSTextField, _ option: Option, _ caption: String,
                    min: Double, max: Double, _ action: Selector) {
            s.minValue = min
            s.maxValue = max
            s.target = self
            s.action = action
            s.isContinuous = true
            s.controlSize = .small
            value.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            value.textColor = .secondaryLabelColor
            let c = NSTextField(labelWithString: caption)
            c.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            c.textColor = .secondaryLabelColor
            captions[option] = c
            for v in [c, s, value] as [NSView] { contentView.addSubview(v) }
        }
        slider(sizeSlider, sizeValue, .size, "Size", min: 1, max: 96, #selector(sizeChanged(_:)))
        slider(strokeSlider, strokeValue, .width, "Width", min: 1, max: 48, #selector(strokeChanged(_:)))
        slider(toleranceSlider, toleranceValue, .tolerance, "Tolerance", min: 0, max: 255,
               #selector(toleranceChanged(_:)))
        slider(wandSlider, wandValue, .wandTolerance, "Tolerance", min: 0, max: 255,
               #selector(wandChanged(_:)))

        styleControl.target = self
        styleControl.action = #selector(styleChanged(_:))
        styleControl.font = Self.shapeStyleFont
        styleControl.controlSize = .small
        for (i, segment) in Self.shapeStyleSegments.enumerated() {
            styleControl.setWidth(Self.shapeStyleSegmentWidth, forSegment: i)
            styleControl.setToolTip(segment.help, forSegment: i)
        }
        contentView.addSubview(styleControl)

        fontButton.bezelStyle = .push
        fontButton.controlSize = .small
        fontButton.font = NSFont.systemFont(ofSize: 11)
        fontButton.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        fontButton.imagePosition = .imageLeading
        fontButton.target = self
        fontButton.action = #selector(fontClicked(_:))
        fontButton.toolTip = "Choose the font (⌘T)"
        contentView.addSubview(fontButton)

        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func views(for option: Option) -> [NSView] {
        switch option {
        case .size: return [captions[.size]!, sizeSlider, sizeValue]
        case .width: return [captions[.width]!, strokeSlider, strokeValue]
        case .tolerance: return [captions[.tolerance]!, toleranceSlider, toleranceValue]
        case .wandTolerance: return [captions[.wandTolerance]!, wandSlider, wandValue]
        case .style: return [styleControl]
        case .font: return [fontButton]
        }
    }

    /// The options actually on show, read off the controls rather than the table, so a
    /// check of this is a check of what the user sees.
    var visibleOptions: [Option] {
        Option.allCases.filter { opt in
            views(for: opt).allSatisfy { !$0.isHidden && contentView.bounds.contains($0.frame) }
        }
    }

    func refresh() {
        let tool = settings.tool
        sizeSlider.doubleValue = Double(settings.brushSize)
        strokeSlider.doubleValue = Double(settings.strokeWidth)
        toleranceSlider.doubleValue = Double(settings.tolerance)
        wandSlider.doubleValue = Double(settings.wandTolerance)
        sizeValue.stringValue = "\(Int(settings.brushSize)) px"
        strokeValue.stringValue = "\(Int(settings.strokeWidth)) px"
        toleranceValue.stringValue = "\(settings.tolerance)"
        wandValue.stringValue = "\(settings.wandTolerance)"
        styleControl.selectedSegment = settings.shapeStyle.rawValue
        fontButton.title = "\(settings.font.displayName ?? settings.font.fontName) "
            + "\(Int(settings.font.pointSize.rounded())) pt"

        icon.image = NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        nameLabel.stringValue = tool.title
        keycap.key = tool.key.uppercased()
        hintLabel.stringValue = Self.hint(for: tool) ?? ""
        relayout(for: tool)
    }

    /// The widest the island may be, set by whoever places it. On a narrow window it
    /// gives up the hint first and then some slider length, rather than run off the edge.
    var maxWidth: CGFloat = .greatestFiniteMagnitude {
        didSet { if maxWidth != oldValue { relayout(for: settings.tool) } }
    }

    private func relayout(for tool: Tool) {
        for (slider, hint) in [(CGFloat(120), true), (120, false), (80, false), (56, false)] {
            if layOut(tool: tool, sliderWidth: slider, withHint: hint) <= maxWidth { break }
        }
    }

    /// Lays the island out one way and returns how wide that made it.
    @discardableResult
    private func layOut(tool: Tool, sliderWidth: CGFloat, withHint: Bool) -> CGFloat {
        let h = Self.height
        let shown = Self.options(for: tool)
        for opt in Option.allCases { views(for: opt).forEach { $0.isHidden = !shown.contains(opt) } }

        var x: CGFloat = 16
        func place(_ v: NSView, width: CGFloat, height: CGFloat, after gap: CGFloat) {
            v.frame = CGRect(x: x, y: ((h - height) / 2).rounded(), width: width, height: height)
            x += width + gap
        }
        func textWidth(_ f: NSTextField) -> CGFloat { ceil(f.intrinsicContentSize.width) + 3 }

        place(icon, width: 20, height: 20, after: 8)
        place(nameLabel, width: textWidth(nameLabel), height: 17, after: 7)
        place(keycap, width: 18, height: 18, after: 0)

        let hasHint = withHint && !(hintLabel.stringValue.isEmpty)
        let hasMore = !shown.isEmpty || hasHint
        rule.isHidden = !hasMore
        if hasMore {
            x += 14
            place(rule, width: 1, height: 20, after: 14)
        }
        for opt in shown {
            switch opt {
            case .size, .width, .tolerance, .wandTolerance:
                let parts = views(for: opt)
                let caption = parts[0] as! NSTextField, slider = parts[1], value = parts[2] as! NSTextField
                place(caption, width: textWidth(caption), height: 16, after: 8)
                place(slider, width: sliderWidth, height: 18, after: 8)
                // Wide enough for "96 px" and "255", so the island does not twitch as it moves.
                place(value, width: 38, height: 15, after: 14)
            case .style:
                place(styleControl, width: 3 * Self.shapeStyleSegmentWidth + 4, height: 22, after: 14)
            case .font:
                fontButton.sizeToFit()
                place(fontButton, width: min(220, fontButton.frame.width + 8), height: 24, after: 14)
            }
        }
        hintLabel.isHidden = !hasHint
        if hasHint {
            place(hintLabel, width: textWidth(hintLabel), height: 16, after: 14)
        }
        let width = x + (hasMore ? 2 : 16)
        if abs(shapeFrame.width - width) > 0.5 || shapeFrame.height != h {
            shapeFrame = CGRect(x: shapeFrame.minX, y: shapeFrame.minY, width: width, height: h)
            onResize?()
        }
        return width
    }

    @objc private func sizeChanged(_ s: NSSlider) { onInteraction?(); settings.brushSize = CGFloat(s.doubleValue.rounded()) }
    @objc private func strokeChanged(_ s: NSSlider) { onInteraction?(); settings.strokeWidth = CGFloat(s.doubleValue.rounded()) }
    @objc private func toleranceChanged(_ s: NSSlider) { onInteraction?(); settings.tolerance = Int(s.doubleValue) }
    @objc private func wandChanged(_ s: NSSlider) { onInteraction?(); settings.wandTolerance = Int(s.doubleValue) }
    @objc private func styleChanged(_ s: NSSegmentedControl) {
        onInteraction?()
        settings.shapeStyle = ShapeStyle(rawValue: s.selectedSegment) ?? .outline
    }
    @objc private func fontClicked(_ sender: Any?) { onInteraction?(); onChooseFont?() }
}

/// The colours: one line of the two colours in play and the most-used swatches, which
/// opens upward into the whole palette when asked — the island's trick again.
final class ColorCapsule: GlassPanel {
    static let collapsedHeight: CGFloat = 50
    static let cell: CGFloat = 26
    static let pad: CGFloat = 10
    static let quickCount = 8
    static let gridColumns = 12

    private let settings: ToolSettings
    let wells = ColorWellsView()
    private let swap = NSButton()
    private let rule = NSBox()
    private(set) var quickSwatches: [SwatchButton] = []
    private(set) var gridSwatches: [SwatchButton] = []
    let expandButton = NSButton()
    let pickerButton = NSButton(title: "More Colours…", target: nil, action: nil)
    private let grid = NSView()
    private(set) var isExpanded = false

    var onInteraction: (() -> Void)?
    var onColorPanelRequest: ((Bool) -> Void)?
    /// Called when the capsule changes size, so the owner can re-anchor it.
    var onResize: (() -> Void)?

    static var width: CGFloat {
        let row = pad + ColorWellsView.size.width + 2 + 22 + 17 + CGFloat(quickCount) * cell + 4 + 28 + pad
        let gridWidth = 2 * pad + CGFloat(gridColumns) * cell
        return max(row, gridWidth)
    }
    static var gridRows: Int { (StandardPalette.colors.count + gridColumns - 1) / gridColumns }
    static var expandedHeight: CGFloat {
        collapsedHeight + CGFloat(gridRows) * cell + 8 + 26 + 10
    }

    init(settings: ToolSettings) {
        self.settings = settings
        super.init(cornerRadius: Self.collapsedHeight / 2)
        let h = Self.collapsedHeight
        // Sized before anything is added, so the autoresizing below starts from the truth.
        shapeFrame = CGRect(x: 0, y: 0, width: Self.width, height: h)

        // The bottom row, pinned to the bottom so it stays put while the capsule opens.
        var x = Self.pad
        wells.frame = CGRect(x: x, y: (h - ColorWellsView.size.height) / 2,
                             width: ColorWellsView.size.width, height: ColorWellsView.size.height)
        wells.toolTip = "Line colour in front, second colour behind. Click either to choose."
        wells.onPickForeground = { [weak self] in self?.onInteraction?(); self?.onColorPanelRequest?(true) }
        wells.onPickBackground = { [weak self] in self?.onInteraction?(); self?.onColorPanelRequest?(false) }
        x += ColorWellsView.size.width + 2

        swap.isBordered = false
        swap.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "Swap colours")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        swap.contentTintColor = .secondaryLabelColor
        swap.frame = CGRect(x: x, y: (h - 22) / 2, width: 22, height: 22)
        swap.target = self
        swap.action = #selector(swapClicked(_:))
        swap.toolTip = "Swap the two colours (⇧⌘X)"
        x += 22 + 8

        rule.boxType = .separator
        rule.frame = CGRect(x: x, y: (h - 22) / 2, width: 1, height: 22)
        x += 9

        for v in [wells, swap, rule] as [NSView] {
            v.autoresizingMask = [.maxYMargin]
            contentView.addSubview(v)
        }

        for c in StandardPalette.quick {
            let s = makeSwatch(c)
            s.frame = CGRect(x: x, y: (h - Self.cell) / 2, width: Self.cell, height: Self.cell)
            s.autoresizingMask = [.maxYMargin]
            contentView.addSubview(s)
            quickSwatches.append(s)
            x += Self.cell
        }
        x += 4

        expandButton.isBordered = false
        expandButton.frame = CGRect(x: x, y: (h - 28) / 2, width: 28, height: 28)
        expandButton.autoresizingMask = [.maxYMargin]
        expandButton.target = self
        expandButton.action = #selector(expandClicked(_:))
        expandButton.contentTintColor = .secondaryLabelColor
        contentView.addSubview(expandButton)

        // The whole palette, standing on top of the row and pinned to it, so it is
        // uncovered as the capsule grows upward; hidden while closed.
        grid.frame = CGRect(x: 0, y: h, width: Self.width, height: Self.expandedHeight - h)
        grid.autoresizingMask = [.maxYMargin]
        let gridLeft = (Self.width - CGFloat(Self.gridColumns) * Self.cell) / 2
        let top = grid.frame.height - 10
        for (i, c) in StandardPalette.colors.enumerated() {
            let col = i % Self.gridColumns, row = i / Self.gridColumns
            let s = makeSwatch(c)
            s.frame = CGRect(x: gridLeft + CGFloat(col) * Self.cell,
                             y: top - CGFloat(row + 1) * Self.cell, width: Self.cell, height: Self.cell)
            grid.addSubview(s)
            gridSwatches.append(s)
        }
        pickerButton.bezelStyle = .push
        pickerButton.controlSize = .small
        pickerButton.font = NSFont.systemFont(ofSize: 11)
        pickerButton.image = NSImage(systemSymbolName: "eyedropper.halffull", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium))
        pickerButton.imagePosition = .imageLeading
        pickerButton.target = self
        pickerButton.action = #selector(pickerClicked(_:))
        pickerButton.sizeToFit()
        pickerButton.frame = CGRect(x: (Self.width - pickerButton.frame.width - 8) / 2,
                                    y: top - CGFloat(Self.gridRows) * Self.cell - 8 - 22,
                                    width: pickerButton.frame.width + 8, height: 22)
        grid.addSubview(pickerButton)
        grid.isHidden = true
        contentView.addSubview(grid)

        updateExpandButton()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func makeSwatch(_ c: NSColor) -> SwatchButton {
        let s = SwatchButton(color: c)
        s.toolTip = "Click: line colour · Right-click: second colour"
        s.onLeft = { [weak self] c in self?.onInteraction?(); self?.settings.foreground = c }
        s.onRight = { [weak self] c in self?.onInteraction?(); self?.settings.background = c }
        return s
    }

    private func updateExpandButton() {
        let name = isExpanded ? "chevron.down" : "chevron.up"
        expandButton.image = NSImage(systemSymbolName: name, accessibilityDescription: isExpanded ? "Fewer colours" : "All colours")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        expandButton.toolTip = isExpanded ? "Fewer colours" : "All colours"
    }

    /// Opens or closes the full palette, growing upward from the bottom edge.
    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        updateExpandButton()
        var target = shapeFrame
        target.size.height = expanded ? Self.expandedHeight : Self.collapsedHeight
        let radius: CGFloat = expanded ? 22 : Self.collapsedHeight / 2
        let outer = target.insetBy(dx: -GlassPanel.outset, dy: -GlassPanel.outset)
        if expanded { grid.isHidden = false; grid.alphaValue = animated ? 0 : 1 }
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.32
                // A slight overshoot, so it lands the way the Island does rather than stopping dead.
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.15, 0.4, 1)
                ctx.allowsImplicitAnimation = true
                self.animator().frame = outer
                self.grid.animator().alphaValue = expanded ? 1 : 0
            }, completionHandler: { [weak self] in
                guard let self else { return }
                if !self.isExpanded { self.grid.isHidden = true }
                self.cornerRadius = radius
            })
            if expanded { cornerRadius = radius }
        } else {
            frame = outer
            cornerRadius = radius
            grid.isHidden = !expanded
        }
        onResize?()
    }

    func refresh() {
        wells.foreground = settings.foreground
        wells.background = settings.background
        let fg = settings.foreground.usingColorSpace(.sRGB)
        for s in quickSwatches + gridSwatches {
            s.isSelected = fg.map { Self.same(s.color, $0) } ?? false
        }
    }

    private static func same(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a = a.usingColorSpace(.sRGB) else { return false }
        return abs(a.redComponent - b.redComponent) < 0.002 && abs(a.greenComponent - b.greenComponent) < 0.002
            && abs(a.blueComponent - b.blueComponent) < 0.002 && abs(a.alphaComponent - b.alphaComponent) < 0.002
    }

    @objc private func swapClicked(_ sender: Any?) { onInteraction?(); settings.swapColors() }
    @objc private func expandClicked(_ sender: Any?) { setExpanded(!isExpanded, animated: true) }
    @objc private func pickerClicked(_ sender: Any?) { onInteraction?(); onColorPanelRequest?(true) }
}

/// The three panels together, and where they go over a canvas area.
final class FloatingPalette {
    let dock: ToolDock
    let island: OptionsIsland
    let colors: ColorCapsule
    private let settings: ToolSettings
    /// The canvas area the panels were last laid out over, to re-anchor them when one
    /// changes size on its own.
    private var area: CGRect = .zero

    var onInteraction: (() -> Void)? {
        didSet { island.onInteraction = onInteraction; colors.onInteraction = onInteraction }
    }
    var onColorPanelRequest: ((Bool) -> Void)? { didSet { colors.onColorPanelRequest = onColorPanelRequest } }
    var onChooseFont: (() -> Void)? { didSet { island.onChooseFont = onChooseFont } }

    init(settings: ToolSettings) {
        self.settings = settings
        dock = ToolDock()
        island = OptionsIsland(settings: settings)
        colors = ColorCapsule(settings: settings)
        dock.onSelect = { [weak self] tool in
            guard let self else { return }
            // Using the dock is using the app, exactly as the Tools menu is: whatever is
            // still in mid-air over the bitmap is settled before the click takes effect.
            self.onInteraction?()
            self.settings.tool = tool
            self.refresh()
        }
        island.onResize = { [weak self] in self?.relayout() }
        colors.onResize = { [weak self] in self?.relayout() }
        refresh()
    }

    var panels: [GlassPanel] { [dock, island, colors] }

    func install(in view: NSView) {
        for p in panels { view.addSubview(p) }
    }

    func refresh() {
        dock.refresh(current: settings.tool)
        island.refresh()
        colors.refresh()
    }

    /// Places the panels over `area`, the canvas's rectangle in the superview.
    func layout(in area: CGRect) {
        self.area = area
        relayout()
    }

    private func relayout() {
        guard area.width > 0 else { return }
        let inset = Theme.panelInset
        // The dock: left edge, centred vertically, in as few columns as fit.
        let cols = ToolDock.columns(toFit: area.height - 2 * inset)
        if cols != dock.columns { dock.arrange(columns: cols) }
        let dh = ToolDock.height(columns: cols), dw = ToolDock.width(columns: cols)
        dock.shapeFrame = CGRect(x: area.minX + inset, y: (area.midY - dh / 2).rounded(), width: dw, height: dh)

        // The island and the colours are centred on the canvas, but never over the dock.
        let clearLeft = dock.shapeFrame.maxX + inset
        func centred(_ width: CGFloat) -> CGFloat {
            max(clearLeft, (area.midX - width / 2).rounded())
        }
        let room = area.maxX - inset - clearLeft
        if island.maxWidth != room { island.maxWidth = room }
        let iw = island.shapeFrame.width
        island.shapeFrame = CGRect(x: centred(iw), y: area.maxY - inset - OptionsIsland.height,
                                   width: iw, height: OptionsIsland.height)
        let cs = colors.shapeFrame.size
        colors.shapeFrame = CGRect(x: centred(cs.width), y: area.minY + inset, width: cs.width, height: cs.height)
    }

    /// How much of the canvas area the panels cover at its edges, for zoom-to-fit to
    /// leave clear. Symmetric, because the clip view centres the picture.
    var fitMargins: CGSize {
        let inset = Theme.panelInset
        let side = dock.shapeFrame.width + 2 * inset
        let vertical = max(OptionsIsland.height, ColorCapsule.collapsedHeight) + 2 * inset
        return CGSize(width: side, height: vertical)
    }
}
