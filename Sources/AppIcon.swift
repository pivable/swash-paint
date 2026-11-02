import AppKit

/// The app icon, drawn in code.
///
/// There is no Xcode here and no asset catalog, so the icon is drawn by the app itself:
/// `build.sh` runs `Paintbox --iconset DIR` on the binary it has just compiled and hands
/// the PNGs to `iconutil`, which ships with macOS. That keeps the whole build to tools
/// every Mac with the Command Line Tools already has — which `install.sh` depends on,
/// because it builds on the user's machine.
///
/// The shape follows the macOS 26 grid: a continuous-corner rounded square 824 units
/// across on a 1024 canvas, with the margin left for the shadow. On it, a warm-to-violet
/// wash, a sheen of light across the top, and a single white brush swash with a spark.
enum AppIcon {
    /// Every file `iconutil` expects in an .iconset, and its size in pixels.
    static let iconsetFiles: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    private static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: a)
    }

    /// The tile's outline in 1024-unit space: a superellipse, which is what gives Apple's
    /// icons their continuous corners — a plain rounded rectangle has a visible kink
    /// where each straight edge meets its arc.
    static func tilePath() -> CGPath {
        let centre = CGPoint(x: 512, y: 512), half: CGFloat = 412, n: CGFloat = 5
        let p = CGMutablePath()
        let steps = 360
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = centre.x + half * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
            let y = centre.y + half * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        p.closeSubpath()
        return p
    }

    /// The logo's stroke, in 1024-unit space, as the dabs a brush would lay down: fine
    /// where it lands, full in the middle, lifting off at the end. Shared with the demo
    /// picture, which paints the same mark with the app's own brush.
    static func swashDabs(samples: Int = 240) -> [(at: CGPoint, radius: CGFloat)] {
        let p0 = CGPoint(x: 250, y: 740), p1 = CGPoint(x: 330, y: 470)
        let p2 = CGPoint(x: 600, y: 700), p3 = CGPoint(x: 700, y: 400)
        return (0...samples).map { i in
            let t = CGFloat(i) / CGFloat(samples), u = 1 - t
            let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
            let p = CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                            y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
            return (p, 14 + 62 * sin(.pi * pow(t, 0.75)))
        }
    }

    /// The logo's four-point spark, in 1024-unit space.
    static func sparkPath(centre mid: CGPoint = CGPoint(x: 762, y: 258), radius r: CGFloat = 78,
                          waist: CGFloat = 18) -> CGPath {
        let spark = CGMutablePath()
        for i in 0..<4 {
            let a = CGFloat(i) * .pi / 2
            let tip = CGPoint(x: mid.x + r * cos(a), y: mid.y + r * sin(a))
            let next = CGPoint(x: mid.x + r * cos(a + .pi / 2), y: mid.y + r * sin(a + .pi / 2))
            let ctl = CGPoint(x: mid.x + waist * cos(a + .pi / 4), y: mid.y + waist * sin(a + .pi / 4))
            if i == 0 { spark.move(to: tip) }
            spark.addQuadCurve(to: next, control: ctl)
        }
        spark.closeSubpath()
        return spark
    }

    /// The icon at `pixels` square, transparent outside the tile.
    static func render(pixels: Int) -> CGImage {
        let ctx = Bitmap.makeContext(width: pixels, height: pixels)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        ctx.withTopLeftOrigin { c in
            // Shadows are measured in pixels whatever the transform says, so they are
            // scaled by hand; unscaled, a 16px icon wore a 34px blur and became a grey box.
            let k = CGFloat(pixels) / 1024
            c.scaleBy(x: k, y: k)
            let tile = tilePath()

            // The shadow the tile casts, under it only.
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 34 * k, color: rgb(0x000000, 0.32))
            c.addPath(tile)
            c.setFillColor(rgb(0x6A5CFF))
            c.fillPath()
            c.restoreGState()

            c.saveGState()
            c.addPath(tile)
            c.clip()
            // The wash.
            let wash = CGGradient(colorsSpace: space,
                                  colors: [rgb(0xFFB25B), rgb(0xFF5A86), rgb(0x8B5CF6), rgb(0x4F46E5)] as CFArray,
                                  locations: [0, 0.38, 0.72, 1])!
            c.drawLinearGradient(wash, start: CGPoint(x: 160, y: 120), end: CGPoint(x: 880, y: 920), options: [])
            // A glow low on the right, so the colour is not one flat ramp.
            let glow = CGGradient(colorsSpace: space, colors: [rgb(0x60A5FA, 0.55), rgb(0x60A5FA, 0)] as CFArray,
                                  locations: [0, 1])!
            c.drawRadialGradient(glow, startCenter: CGPoint(x: 820, y: 860), startRadius: 0,
                                 endCenter: CGPoint(x: 820, y: 860), endRadius: 420, options: [])
            // The sheen: light across the upper half, as on glass.
            let sheen = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.34), rgb(0xFFFFFF, 0)] as CFArray,
                                   locations: [0, 1])!
            c.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 560), options: [])

            // The stroke: one swash of a loaded brush, stamped along a curve as a brush stamps.
            let swash = CGMutablePath()
            for dab in swashDabs() {
                swash.addEllipse(in: CGRect(x: dab.at.x - dab.radius, y: dab.at.y - dab.radius,
                                            width: 2 * dab.radius, height: 2 * dab.radius))
            }
            c.saveGState()
            c.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 26 * k, color: rgb(0x2E1065, 0.35))
            c.beginTransparencyLayer(auxiliaryInfo: nil)
            c.addPath(swash)
            c.setFillColor(rgb(0xFFFFFF))
            c.fillPath(using: .winding)
            c.endTransparencyLayer()
            c.restoreGState()

            // The spark, top right, where the stroke is heading.
            let spark = sparkPath()
            c.addPath(spark)
            c.setFillColor(rgb(0xFFF7D6))
            c.fillPath()
            c.restoreGState()

            // A hairline of light round the rim, which is what makes it read as a surface.
            c.addPath(tile)
            c.setLineWidth(5)
            c.setStrokeColor(rgb(0xFFFFFF, 0.28))
            c.strokePath()
        }
        return ctx.makeImage()!
    }

    /// Writes every size into `dir`, which becomes an .iconset for `iconutil`.
    static func writeIconset(to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in iconsetFiles {
            let rep = NSBitmapImageRep(cgImage: render(pixels: file.pixels))
            guard let data = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: dir.appendingPathComponent(file.name))
        }
    }
}
