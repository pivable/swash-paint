# Paintbox: working on it

**Read this before changing anything here.** `README.md` is for people who use the app; this is
for whoever works on it. It is deliberately short, and every line in it is something that has
already cost somebody an hour.

**What it is:** a native macOS drawing and image-editing app, in the spirit of MS Paint, whose
one genuinely differentiated feature is background removal that runs on the machine. Free,
MIT, public at **github.com/pivable/paintbox** since 2026-09-23.

---

## The environment, which is not what you expect

**Xcode is NOT installed on this Mac, and the project does not want it.** There is no
`.xcodeproj`, no `xcodebuild`, no Swift package. `swiftc` compiles `Sources/*.swift` straight
into a bundle that `build.sh` assembles by hand and ad-hoc signs.

```
./build.sh                  # the ONLY build command
./build.sh --universal      # Intel as well as Apple Silicon — use for anything you hand out
./build.sh --package        # also produce Paintbox.zip and print the recipient's instructions
```

AppKit, not SwiftUI. That was chosen because this is a pixel editor with a custom canvas view,
and a declarative layer fights you for no gain.

## Prove it works before you believe it

```
./Paintbox.app/Contents/MacOS/Paintbox --selftest
```

**221 checks, exit 0. Never let that number go down.** They assert real pixels rather than that
the code ran: that right-angle rotation is lossless, that alpha survives all seven save
formats, that a blur leaves every pixel outside the selection untouched, that undo restores
byte for byte, and that background removal actually finds a subject.

Two more entry points, and both matter because `screencapture` returns black on this machine:

```
--screenshot out.png        # renders the real window's view tree to a PNG. This is how you SEE it.
                            # PAINTBOX_APPEARANCE=dark (or light) picks the appearance.
--iconset DIR.iconset       # draws the app icon at every size; build.sh runs it, then iconutil
--cutout in.jpg out.png     # background removal, headless, format from the output extension
```

**What `--screenshot` cannot draw, and what it does instead.** `cacheDisplay` renders every
`NSGlassEffectView` as an opaque white slab — the toolbar's buttons each stand on one on
macOS 26, so in dark mode every toolbar glyph (white) vanished into white. That was the
screenshot, never the app: the glyphs are plain template SF Symbols. `GlassSnapshot`
(Theme.swift) swaps each glass view for a drawn stand-in while the picture is taken, and
the window is made to draw as key, since a process started from a terminal may not take
the focus. Blur behind glass is the one thing the stand-in does not reproduce.

**The layout.** The canvas has the full window width; tools (`ToolDock`), the current
tool's options (`OptionsIsland`) and colours (`ColorCapsule`) float over it as
`GlassPanel`s, all in `FloatingPanels.swift`. A panel's view is larger than the panel by
`GlassPanel.outset`, and draws its own soft shadow there, because layer shadows do not
survive `cacheDisplay`; clicks in that margin fall through. `NSGlassEffectView` is behind
`#if compiler(>=6.2)` as well as `#available(macOS 26.0, *)`, because install.sh builds on
the user's machine and an older SDK has no such symbol.

**A green suite is not the running system.** Every mouse interaction — the drawing tools, the
shift constraints, the floating-paste handles, the dialogs — is verified only by code. When you
change any of it, take a screenshot and look.

## House style

- **Comments explain WHY, never what.** Match the surrounding files; they are the specification.
- **Add a self-test with every fix**, in the style of `Sources/SelfTest.swift`, asserting real
  pixels or real state. A fix with no test regresses silently and we have watched it happen.
- Several files, no monolith. `Sources/` is already split by concern.
- **Never weaken a test to make something pass.** A prover agent specifically hunts for loosened
  assertions, deleted tests and removed guards, and it will find it.

## Traps this project has already fallen into

Each of these was a real bug here, and each is the kind that looks fine until it doesn't.

- **The selection is a per-pixel MASK, not a rectangle.** It has to be, for the magic wand and
  for filtering an irregular region. Anything that quietly uses the bounding box instead is
  probably wrong — except Crop, which genuinely cannot be non-rectangular.
- **Coordinate systems disagree.** AppKit views and CGContext are bottom-left origin; image rows
  are top-left. Every conversion is a chance for an upside-down result or an off-by-one. Paste
  landed upside down once for exactly this reason.
- **Retina.** Get the backing scale wrong and every export is blurry or half size.
- **Premultiplied alpha.** The canonical bitmap is RGBA8 premultiplied-last in sRGB. Filtering
  premultiplied data as though it were straight darkens semi-transparent edges.
- **`CIPixellate`'s centre parameter is a block CORNER, not a centre.** That put the grid ten
  pixels out.
- **Filters must run over a padded region, never a cropped one.** Cropping first is what makes
  a blur bleed transparency in from outside the selection.
- **Brush spacing belongs to the STROKE, not to the mouse event.** Restarting it per event made
  the same drag up to 138 alpha levels harder when delivered as many small events, which is an
  ordinary slow drag or any drag at zoom.
- **A `dev.host` style config copied from elsewhere can drop the port** and silently break
  anything that builds a URL.

## How people install it, and why it is shaped that way

```
curl -fsSL https://raw.githubusercontent.com/pivable/paintbox/main/install.sh | bash
```

That fetches the source, builds it on the user's own machine, runs the tests, and only then
installs. **The reason is Gatekeeper.** Anything downloaded through a browser is quarantined,
and this app is ad-hoc signed rather than notarised, so macOS refuses it — and since Sequoia the
right-click-to-open shortcut is gone, leaving System Settings. A `.command` script is not a
loophole; it gets quarantined too, which was tested.

**An app built on the machine that will run it is never quarantined at all.** That is the whole
trick, and it costs nothing. The alternative is the Apple Developer Program at 99 USD a year,
which would let a plain download just work. Nothing in the code changes either way.

`Build.command` is double-clickable for anyone who cloned the repository, where there is no
quarantine flag to fight.

**Check for Updates runs that same installer** (`Updater.swift` decides, `UpdateUI.swift`
shows). Things it depends on, each easy to break from the other side:

- **The version is the commit.** `build.sh` stamps `PaintboxCommit` (and the commit's date,
  and the build date) into Info.plist. A clone answers through git; the tarball path in
  `install.sh` reads the commit from the tarball's pax `comment=` header and passes it as
  `PAINTBOX_COMMIT`. No stamp means "cannot tell", which offers the update, never "up to date".
- **The app reads install.sh's step lines** ("Fetching the source...", "Building...",
  "Checking it works...", "Installing to ...", and "Installed to " as proof of success) to
  drive its progress sheet. Change those words and change `UpdateInstall.phase(forLine:)`.
- **`PAINTBOX_DEST`** is the folder holding the running bundle; **`PAINTBOX_NO_OPEN=1`** stops
  the installer opening the app, because the app offers Relaunch Now itself.
- **install.sh never deletes the old copy first.** It copies the new one in under a hidden
  name, verifies it, then swaps; its EXIT trap puts the old one back if it is stopped mid-swap.
- **Testing an unpushed installer:** launch the app with `PAINTBOX_INSTALLER=/path/install.sh`
  (used instead of the one on GitHub) and `PAINTBOX_REPO=file:///path/to/clone` (what that
  installer clones). The check itself always asks the real GitHub. Install into a scratch
  folder with `PAINTBOX_DEST`, never /Applications, and build it with an older
  `PAINTBOX_COMMIT` to make it look out of date.
- **The self-test never touches the network.** `UpdateFetching` is the seam; the suite's
  stub records every URL it is asked for, and the toggle tests use a scratch defaults domain.

## Where things are written down

| | |
|---|---|
| `README.md` | For users: what it does, shortcuts, rough edges. Keep it TRUE — three claims in it were false once and that is how you lose trust on a first impression. |
| `KNOWN-ISSUES.md` | What the completeness critic found, and what became of each. None open since 2 Nov 2026. |
| `REVIEW-BACKLOG.md` | How the review was run and what it cost. History, not a to-do list. |
| this file | How to work on it. |

## What to pick up next

`KNOWN-ISSUES.md` has nothing open: the six the critic left were fixed on 2 Nov 2026, each
with a self-test. The honest list of what this app still is not is in `README.md` under
*Deliberately not built* and *Known rough edges* — most usefully: the selection cannot be
picked up and moved, there is no feathering, and there are no layers beyond a single
floating item.
