import AppKit
import CoreGraphics

let arguments = CommandLine.arguments

/// What the command line asked for, decided in one place before anything runs.
///
/// Each entry point used to look for its own flag and fall through to the GUI when it
/// did not find it, so `--self-test`, `--cutout photo.jpg` with the output forgotten, or
/// `--help` all opened a window and said nothing — on a terminal, which is exactly where
/// nobody is looking at the Dock. A double-dash word Paintbox does not know is now an
/// error with the usage on stderr and exit 64 (EX_USAGE).
///
/// Only `--` words are judged. macOS hands GUI launches arguments of its own — `-psn_…`
/// from older launchers, `-NSSomeDefault value` and `-AppleLanguages (…)` from anything
/// that sets a default for one run — and a bare path is a file to open. Those all still
/// reach AppKit untouched.
enum CommandLineRoute: Equatable {
    case gui
    case selftest
    case cutout(input: String, output: String)
    case screenshot(output: String)
    case iconset(output: String)
    case help
    case usageError(String)

    static let usage = """
        usage: Paintbox                          open the app
               Paintbox --selftest               run the self-tests, exit 0 when all pass
               Paintbox --cutout IN OUT          remove the background from IN, write OUT
               Paintbox --screenshot OUT.png     render the window to a PNG
               Paintbox --iconset DIR.iconset    draw the app icon at every size (build.sh uses it)
               Paintbox --help
        """

    static func parse(_ args: [String]) -> CommandLineRoute {
        let rest = Array(args.dropFirst())
        guard let i = rest.firstIndex(where: { $0.hasPrefix("--") || $0 == "-h" }) else { return .gui }
        let flag = rest[i]
        // Whatever follows a flag that takes operands, and is not itself a flag.
        func operands(_ n: Int) -> [String]? {
            let tail = rest.dropFirst(i + 1).prefix(n)
            guard tail.count == n, !tail.contains(where: { $0.hasPrefix("--") }) else { return nil }
            return Array(tail)
        }
        let result: CommandLineRoute
        let used: Int
        switch flag {
        case "--selftest":
            result = .selftest; used = 0
        case "--help", "-h":
            result = .help; used = 0
        case "--cutout":
            guard let o = operands(2) else { return .usageError("--cutout needs an input and an output file") }
            result = .cutout(input: o[0], output: o[1]); used = 2
        case "--screenshot":
            guard let o = operands(1) else { return .usageError("--screenshot needs an output file") }
            result = .screenshot(output: o[0]); used = 1
        case "--iconset":
            guard let o = operands(1) else { return .usageError("--iconset needs an output folder") }
            result = .iconset(output: o[0]); used = 1
        default:
            return .usageError("unknown option \(flag)")
        }
        // A second flag after the first is a typo or a misunderstanding, not something to
        // silently ignore: `--cutout a b --selftest` should not quietly mean one of them.
        if let extra = rest.dropFirst(i + 1 + used).first(where: { $0.hasPrefix("--") }) {
            return .usageError("unexpected \(extra) after \(flag)")
        }
        return result
    }
}

let route = CommandLineRoute.parse(arguments)

switch route {
case .help:
    print(CommandLineRoute.usage)
    exit(0)
case .usageError(let why):
    FileHandle.standardError.write(Data("Paintbox: \(why)\n\(CommandLineRoute.usage)\n".utf8))
    exit(64)
default:
    break
}

if route == .selftest {
    // Headless-ish: AppKit is still needed (NSColor, NSFont, NSBitmapImageRep), but no
    // window is ever shown.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let code = SelfTest.run()
    exit(Int32(code))
}

/*
 * `--cutout in.png out.png` — remove the background from one file, without a window.
 *
 * It exists for two reasons. It lets the background remover be proven on a REAL
 * photograph rather than only on the synthetic figure the self-test draws, which
 * is the thing that would otherwise be taken on trust. And it makes the one
 * genuinely expensive feature in this app scriptable, so a folder of images can
 * be cut out from a shell loop rather than one click at a time.
 *
 * It prints what changed — the corner pixel before and after — so a caller can
 * tell "Vision found a subject" from "Vision found nothing and nothing moved".
 */
enum CutoutCommand {

    /// The whole command as a value: what to print, what to print on the error stream,
    /// and what to exit with. Nothing here prints or exits, so the self-test can run the
    /// real command — and read the real bytes it wrote — inside the same process.
    struct Result {
        var code: Int32
        var out: [String] = []
        var err: String? = nil
    }

    /// The matte for a format that cannot hold transparency. The GUI uses the window's
    /// background swatch; the command line has no window and no swatch, so it says white
    /// here rather than pretending to have an opinion.
    static let matte: NSColor = .white

    static func run(input inURL: URL, output outURL: URL) -> Result {
        // The output format comes from the output's NAME, through `SaveFormat` — the same
        // table the Save As panel offers and the same one `PaintDocument.save` writes by.
        // It used to be `.png` unconditionally, so `--cutout in.jpg out.jpg` wrote a PNG
        // stream into a file called .jpg, and the README's own batch loop names the output
        // after the input: following the instructions produced a folder of files whose
        // extensions lied about their contents. An extension the table does not know is
        // refused rather than guessed at, for the reason ImageFormats.swift already gives
        // about WebP — writing PNG bytes under someone else's name is worse than saying no.
        guard let format = SaveFormat.forExtension(outURL.pathExtension) else {
            let known = SaveFormat.available.map { ".\($0.fileExtension)" }.joined(separator: " ")
            return Result(code: 5,
                          err: "cannot write \(PaintDocument.describe(extension: outURL.pathExtension)). "
                               + "Name the output one of: \(known)")
        }
        guard let source = Bitmap.load(url: inURL) else {
            return Result(code: 2, err: "cannot read \(inURL.path)")
        }
        let before = Bitmap.context(from: source).sample(x: 5, y: 5)
        let cut: CGImage
        do {
            cut = try BackgroundRemover.cutout(from: source)
        } catch {
            return Result(code: 4, err: "no subject found: \(error)")
        }
        let after = Bitmap.context(from: cut).sample(x: 5, y: 5)
        do {
            try Bitmap.write(cut, to: outURL, format: format, matte: matte)
        } catch {
            return Result(code: 6, err: error.localizedDescription)
        }
        let name = format.rawValue.uppercased()
        var out = ["cutout \(source.width)x\(source.height) -> \(outURL.lastPathComponent) (\(name))",
                   "  corner alpha \(before.a) -> \(after.a)"]
        // The corner reading is about the CUT, not about the file, and for a format with
        // no graded alpha those two now disagree on purpose. Say so, or a script reads
        // "corner alpha 255 -> 0" off a JPEG whose corner is solid white.
        switch format.transparency {
        case .graded:
            break
        case .none:
            out.append("  \(name) has no alpha channel: the cut-out was flattened onto white.")
        case .binary:
            out.append("  \(name) transparency is on or off: soft edges were resolved against white.")
        }
        // 3: wrote a file, but the corner is still opaque — Vision found nothing to lift.
        return Result(code: after.a == 0 ? 0 : 3, out: out)
    }
}

if case .cutout(let input, let output) = route {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let result = CutoutCommand.run(input: URL(fileURLWithPath: input),
                                   output: URL(fileURLWithPath: output))
    for line in result.out { print(line) }
    if let err = result.err { FileHandle.standardError.write(Data((err + "\n").utf8)) }
    exit(result.code)
}

if case .iconset(let output) = route {
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    do {
        try AppIcon.writeIconset(to: URL(fileURLWithPath: output))
        print("wrote \(AppIcon.iconsetFiles.count) icon sizes to \(output)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Paintbox: could not write \(output): \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if case .screenshot(let output) = route {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    WindowShot.capture(to: output)
    app.run()
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = PaintboxApp.shared
app.delegate = delegate
app.run()
